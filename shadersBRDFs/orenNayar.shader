Shader "Unlit/GratingWithOrenNayar"
{
    Properties
    {
        _NormalTex1 ("Texture", 2D) = "white" {}
        _NormalTex2 ("Texture", 2D) = "white" {}
        _Cube("Reflection Map", Cube) = "" {}
        _NormalStrength("Bump strength", Float) = 0.2 
        _GratingFrequency("Grating frequency (over u tex coord)", Float) = 2.0
        _Roughness("Roughness", Float) = 0.0
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

            struct gvals
            {
                float factor;
                float grating;
            };

            gvals gratingValue(float2 uv)
            {
                gvals g;
                g.factor = max(abs(ddy(uv.x * _GratingFrequency)), abs(ddx(uv.x * _GratingFrequency))) ;
                g.grating = cos(3.14159 * uv.x * _GratingFrequency);
                g.grating = clamp(g.grating / (0.5 + g.factor * g.factor * g.factor * g.factor), -1.0, 1.0);
                return g;
            }

            float3 gratingNormal(float val, float3 n, float3 t)
            {
                return normalize(t * val + n);
            }

            float3 OrenNayarBRDF(float3 L, float3 V, float3 N, float roughness, float3 albedo)
            {
                float sigma = roughness * roughness;
                float A = 1.0 - 0.5 * (sigma / (sigma + 0.33));
                float B = 0.45 * (sigma / (sigma + 0.09));
                float3 Lp = normalize(L - dot(L, N) * N);
                float3 Vp = normalize(V - dot(V, N) * N);
                float cosThetaL = max(dot(L, N), 0.0);
                float cosThetaV = max(dot(V, N), 0.0);
                float alpha = max(cosThetaL, cosThetaV);
                float beta = min(cosThetaL, cosThetaV);
                float sinAlpha = sqrt(1.0 - alpha * alpha);
                float tanBeta = sinAlpha / beta;

                float C = max(cosThetaL, cosThetaV) * sinAlpha / (cosThetaL + cosThetaV);

                float diff = A + B * max(0.0, dot(Lp, Vp)) * sinAlpha * tanBeta;

                return albedo * (diff / 3.14159265359) * C;
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

                //--------------------------
                // Grating
                //
                gvals g = gratingValue(i.uv);
                float3 normal_grate = gratingNormal(g.grating, normal, tangent);
                float3 normal_grate1 = normalize(clamp(g.grating, 0.0, 1.0) * normal_grate + normal1);
                float3 normal_grate2 = normalize(clamp(1.0 - g.grating, 0.0, 1.0) * normal_grate + normal2);

                //--------------------------
                // Oren-Nayar Lighting
                //
                float3 albedo = float3(1.0, 1.0, 1.0); // Adjust the albedo as needed.
                float3 shadingNear = OrenNayarBRDF(lightdir, viewdir, normal_grate1, _Roughness, albedo);
                float3 shadingFar = OrenNayarBRDF(lightdir, viewdir, normal_grate2, _Roughness, albedo);

                float3 envcolor = lerp(shadingNear, shadingFar, g.factor);

                return fixed4(envcolor, 1.0);
            }
            ENDCG
        }
    }
}