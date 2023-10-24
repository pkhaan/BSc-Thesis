Shader "Custom/CookTorranceWithAO"
{
    Properties
    {
        _NormalTex1 ("Texture", 2D) = "white" {}
        _NormalTex2 ("Texture", 2D) = "white" {}
        _Cube("Reflection Map", Cube) = "" {}
        _NormalStrength("Bump strength", Float) = 0.2 
        _GratingFrequency("Grating frequency (over u tex coord)", Float) = 2.0
        _Roughness("Roughness", Float) = 0.0
        _SpecularColor("Specular Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _AmbientOcclusionTex("Ambient Occlusion", 2D) = "white" {}
        _Color ("Ambient Color", Color) = (1.0, 1.0, 1.0, 1.0)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            sampler2D _NormalTex1;
            sampler2D _NormalTex2;
            samplerCUBE _Cube;
            float4 _NormalTex1_ST;
            float _NormalStrength;
            float _GratingFrequency;
            float _Roughness;
            float3 _SpecularColor;
            sampler2D _AmbientOcclusionTex;
            float4 _Color;

            struct v2f {
                float4 vertex : SV_POSITION;
                float4 vertex_wcs : POSITIONT;
                float3 normal_wcs : NORMAL;
                float3 tangent_wcs : TANGENT;
                float2 uv : TEXCOORD0;
            };

            v2f vert (appdata_full v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.vertex_wcs = mul(unity_ObjectToWorld, v.vertex);
                o.normal_wcs = UnityObjectToWorldNormal(v.normal);
                o.tangent_wcs = UnityObjectToWorldNormal(v.tangent);
                o.uv = TRANSFORM_TEX(v.texcoord, _NormalTex1);
                return o;
            }

            float3 F_Schlick(float3 specularColor, float cosTheta)
            {
                return specularColor + (1.0 - specularColor) * pow(1.0 - cosTheta, 5.0);
            }

            float G_Smith(float3 normal, float3 viewDir, float3 lightDir, float roughness)
            {
                float nDotV = max(dot(normal, viewDir), 0.0);
                float nDotL = max(dot(normal, lightDir), 0.0);
                float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;

                float gl = nDotV / (nDotV * (1.0 - k) + k);
                float gv = nDotL / (nDotL * (1.0 - k) + k);

                return gl * gv;
            }

            float D_GGX(float3 normal, float3 halfwayDir, float roughness)
            {
                float alpha = roughness * roughness;
                float alphaSqr = alpha * alpha;

                float nDotH = max(dot(normal, halfwayDir), 0.0);
                float nDotHSqr = nDotH * nDotH;

                float denom = nDotHSqr * (alphaSqr - 1.0) + 1.0;
                return alphaSqr / (3.14159 * denom * denom);
            }

            struct gvals
            {
                float factor;
                float grating;
            };

            gvals gratingValue(float2 uv)
            {
                gvals g;
                g.factor = max(abs(ddy(uv.x * _GratingFrequency)), abs(ddx(uv.x * _GratingFrequency)));
                g.grating = cos(3.14159 * uv.x * _GratingFrequency);
                g.grating = clamp(g.grating / (0.5 + g.factor * g.factor * g.factor * g.factor), -1.0, 1.0);

                return g;
            }

            float3 gratingNormal(float val, float3 n, float3 t)
            {
                return normalize(t * val + n);
            }

            float3 shade(float3 dir, float roughness, int Nsamples)
            {
                float4 t = float4(dir, roughness * 6.0);
                return texCUBElod(_Cube, t).rgb;
            }

            float3 calculateAmbientOcclusion(float2 uv)
            {
                return tex2D(_AmbientOcclusionTex, uv).rgb;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float4 nmap1 = tex2D(_NormalTex1, i.uv);
                nmap1 = nmap1 * 2.0 - float4(1.0, 1.0, 1.0, 0.0);
                float4 nmap2 = tex2D(_NormalTex2, i.uv);
                nmap2 = nmap2 * 2.0 - float4(1.0, 1.0, 1.0, 0.0);
                float3 normal = normalize(i.normal_wcs);
                float3 tangent = normalize(i.tangent_wcs);
                nmap1.xyz = normalize(nmap1.xyz);
                nmap2.xyz = normalize(nmap2.xyz);

                float3 bitangent = normalize(cross(i.normal_wcs, i.tangent_wcs));
                float3 normal1 = normalize(lerp(normal, (tangent * nmap1.z + bitangent * nmap1.y + normal * nmap1.x), _NormalStrength));
                float3 normal2 = normalize(lerp(normal, (tangent * nmap2.z + bitangent * nmap2.y + normal * nmap2.x), _NormalStrength));

                float4 lightpos = _WorldSpaceLightPos0;
                float3 lightdir = lightpos.w == 0.0 ? lightpos.xyz : normalize(lightpos.xyz - i.vertex_wcs);
                float3 lightcolor = _LightColor0.xyz;
                float3 viewdir = normalize(_WorldSpaceCameraPos - i.vertex_wcs);

                // Cook-Torrance Lighting
                float3 halfwayDir = normalize(lightdir + viewdir);
                float3 fresnelTerm = F_Schlick(_SpecularColor, dot(halfwayDir, viewdir));
                float3 geometricTerm = G_Smith(normal, viewdir, lightdir, _Roughness);
                float3 distributionTerm = D_GGX(normal, halfwayDir, _Roughness);

                float3 specularTerm = (fresnelTerm * geometricTerm * distributionTerm) / (4.0 * max(dot(normal, viewdir), 0.0) * max(dot(normal, lightdir), 0.0) + 0.001);

                // Grating Reflection
                gvals g = gratingValue(i.uv);
                float3 gratingN1 = gratingNormal(g.grating, normal1, tangent);
                float3 gratingN2 = gratingNormal(g.grating, normal2, tangent);
                float3 reflection1 = shade(reflect(-viewdir, gratingN1), _Roughness, 256);
                float3 reflection2 = shade(reflect(-viewdir, gratingN2), _Roughness, 256);
                float3 reflection = lerp(reflection1, reflection2, g.factor);

                // Ambient Occlusion
                float3 ambientOcclusion = calculateAmbientOcclusion(i.uv);

                // Final color
                float3 finalColor = (specularTerm + reflection) * lightcolor + _Color.rgb * ambientOcclusion;

                return float4(finalColor, 1.0);
            }
            ENDCG
        }
    }
}