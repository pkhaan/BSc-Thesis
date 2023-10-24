    // Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

 

Shader "Unlit/Grating"
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

 

        /*
            struct appdata_full {
                 float4 vertex : POSITION;
                 float4 tangent : TANGENT;
                 float3 normal : NORMAL;
                 float4 texcoord : TEXCOORD0;
                 float4 texcoord1 : TEXCOORD1;
                 float4 texcoord2 : TEXCOORD2;
                 float4 texcoord3 : TEXCOORD3;
                 fixed4 color : COLOR;
                 UNITY_VERTEX_INPUT_INSTANCE_ID
        };
        */
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
                g.grating = cos( 3.14159 * uv.x * _GratingFrequency);
                g.grating = clamp( g.grating / (0.5 + g.factor * g.factor * g.factor * g.factor), -1.0, 1.0);

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

 


            fixed4 frag(v2f i) : SV_Target
            {
                float4 nmap1 = tex2D(_NormalTex1, i.uv); 
                nmap1 = nmap1 * 2.0 - float4(1.0, 1.0,1.0, 0.0);
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
                float ndotv = dot(viewdir,normal);
                float3 normal_grate = gratingNormal(g.grating, normal, tangent);
                float3 normal_grate1 = normalize(clamp(g.grating, 0.0, 1.0)* normal_grate + normal1);
                float3 normal_grate2 = normalize(clamp(1.0-g.grating, 0.0, 1.0) * normal_grate + normal2);

 

                int Nsamples = 16;

 

                float3 reflectiondir1 = reflect(-viewdir, normal_grate1);
                float3 reflectiondir2 = reflect(-viewdir, normal_grate2);
                float3 envcolor1 = shade(reflectiondir1, _Roughness, Nsamples);
                float3 envcolor2 = shade(reflectiondir2, _Roughness, Nsamples);

 


                //--------------------------
                // Far shading 
                //
                float3 reflectiondirDistant1 = normalize(reflect(-viewdir,normal1));
                float3 reflectiondirDistant2 = normalize(reflect(-viewdir, normal2));
                float3 envcolorDistant1 = shade(reflectiondirDistant1, _Roughness, Nsamples);
                float3 envcolorDistant2 = shade(reflectiondirDistant2, _Roughness, Nsamples);

 

                //--------------------------
                // Blending
                //
                float distant_blending = 0.5 - 0.5 * dot(tangent, viewdir);
                float near_blending = 0.5 - 0.5 * g.grating;
                float3 shadingNear = lerp(envcolor1, envcolor2, near_blending);
                float3 shadingFar = lerp(envcolorDistant1, envcolorDistant2, distant_blending);

                float3 envcolor = lerp(shadingNear, shadingFar, g.factor);

 

                float ndotl = dot(lightdir, normal);
                float3 shading = /*ndotl * lightcolor*/ envcolor;
                //float3 shading = g.factor * float3(1,1,1);

 

                return fixed4(shading,1.0);
            }
            ENDCG
        }
    }
}







    // Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

    Shader "Custom/CookTorrance"
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

            /* struct appdata_full {
                    float4 vertex : POSITION;
                    float4 tangent : TANGENT;
                    float3 normal : NORMAL;
                    float4 texcoord : TEXCOORD0;
                    UNITY_VERTEX_INPUT_INSTANCE_ID
                };*/

                sampler2D _NormalTex1;
                sampler2D _NormalTex2;
                samplerCUBE _Cube;
                float4 _NormalTex1_ST;
                float _NormalStrength;
                float _GratingFrequency;
                float _Roughness;
                float3 _SpecularColor;  

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

                fixed4 frag(v2f i) : SV_Target
                {


                    // Retrieve the specular color from the shader properties
                    float3 specularColor = _SpecularColor.rgb;   
                    //float4 specularColor = float4(_SpecularColor, 1.0); 


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
                    // Cook-Torrance Lighting
                    //

                    float3 halfwayDir = normalize(lightdir + viewdir);
                    float3 fresnelTerm = F_Schlick(specularColor, dot(halfwayDir, viewdir));
                    float3 geometricTerm = G_Smith(normal, viewdir, lightdir, _Roughness);
                    float3 distributionTerm = D_GGX(normal, halfwayDir, _Roughness);

                    float3 specularTerm = (fresnelTerm * geometricTerm * distributionTerm) / (4.0 * max(dot(normal, viewdir), 0.001));

                    //--------------------------
                    // Grating
                    //

                    gvals g = gratingValue(i.uv);
                    float ndotv = dot(viewdir, normal);
                    float3 normal_grate = gratingNormal(g.grating, normal, tangent);
                    float3 normal_grate1 = normalize(clamp(g.grating, 0.0, 1.0) * normal_grate + normal1);
                    float3 normal_grate2 = normalize(clamp(1.0 - g.grating, 0.0, 1.0) * normal_grate + normal2);

                    int Nsamples = 10;

                    float3 reflectiondir1 = reflect(-viewdir, normal_grate1);
                    float3 reflectiondir2 = reflect(-viewdir, normal_grate2);
                    float3 envcolor1 = shade(reflectiondir1, _Roughness, Nsamples);
                    float3 envcolor2 = shade(reflectiondir2, _Roughness, Nsamples);

                    //--------------------------
                    // Far shading 
                    //

                    float3 reflectiondirDistant1 = normalize(reflect(-viewdir, normal1));
                    float3 reflectiondirDistant2 = normalize(reflect(-viewdir, normal2));
                    float3 envcolorDistant1 = shade(reflectiondirDistant1, _Roughness, Nsamples);
                    float3 envcolorDistant2 = shade(reflectiondirDistant2, _Roughness, Nsamples);

                    //--------------------------
                    // Blending
                    //

                    float distant_blending = 0.5 - 0.5 * dot(tangent, viewdir);
                    float near_blending = 0.5 - 0.5 * g.grating;
                    float3 shadingNear = lerp(envcolor1, envcolor2, near_blending);
                    float3 shadingFar = lerp(envcolorDistant1, envcolorDistant2, distant_blending);

                    float3 envcolor = lerp(shadingNear, shadingFar, g.factor);

                    float ndotl = dot(lightdir, normal);
                    float3 shading = ndotl * lightcolor * envcolor;

                    return fixed4(shading, 1.0);
                }
                ENDCG
            }
        }
    }






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

Shader "Custom/DisneyShader"
{
    Properties
    {
        // Properties for Disney shader
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Roughness ("Roughness", Range(0, 1)) = 0.5
        _Specular ("Specular", Range(0, 1)) = 0.5
        _Subsurface ("Subsurface", Range(0, 1)) = 0
        _SubsurfaceColor ("Subsurface Color", Color) = (1, 1, 1, 1)
        _SpecularTint ("Specular Tint", Range(0, 1)) = 0
        _Anisotropy ("Anisotropy", Range(-1, 1)) = 0
        _Sheen ("Sheen", Range(0, 1)) = 0
        _SheenTint ("Sheen Tint", Range(0, 1)) = 0
        _Clearcoat ("Clearcoat", Range(0, 1)) = 0
        _ClearcoatGloss ("Clearcoat Gloss", Range(0, 1)) = 1

        _NormalTex1 ("Texture", 2D) = "white" {}
        _NormalTex2 ("Texture", 2D) = "white" {}
        _Cube("Reflection Map", Cube) = "" {}
        _NormalStrength("Bump strength", Float) = 0.2 
        _GratingFrequency("Grating frequency (over u tex coord)", Float) = 2.0
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
            #pragma multi_compile_instancing
            #pragma multi_compile_fog

            #include "UnityCG.cginc"
            #include "UnityStandardBRDF.cginc"

            // Custom properties
            sampler2D _NormalTex1;
            sampler2D _NormalTex2;
            samplerCUBE _Cube;
            float4 _NormalTex1_ST;
            float _NormalStrength;
            float _GratingFrequency;

            // Disney shader properties
            float4 _BaseColor;
            float _Metallic;
            float _Roughness;
            float _Specular;
            float _Subsurface;
            float4 _SubsurfaceColor;
            float _SpecularTint;
            float _Anisotropy;
            float _Sheen;
            float _SheenTint;
            float _Clearcoat;
            float _ClearcoatGloss;

            // Other shader properties...

            // Vertex shader
            // ...

            // Fragment shader
            fixed4 frag(v2f i) : SV_Target
            {
                // Normal mapping
                float4 nmap1 = tex2D(_NormalTex1, i.uv);
                nmap1 = nmap1 * 2.0 - float4(1.0, 1.0, 1.0, 0.0);
                float4 nmap2 = tex2D(_NormalTex2, i.uv);
                nmap2 = nmap2 * 2.0 - float4(1.0, 1.0, 1.0, 0.0);
                float3 normal = normalize(i.normal_wcs);
                float3 tangent = normalize(i.tangent_wcs);
                nmap1.xyz = normalize(nmap1.xyz);
                nmap2.xyz = normalize(nmap2.xyz);

                float3 bitangent = normalize(cross(i.normal_wcs, i.tangent_wcs));
                float3 normal1 = normalize(lerp(normal, (tangent * nmap1.z + bitangent * nmap1.y), nmap1.x));
                float3 normal2 = normalize(lerp(normal, (tangent * nmap2.z + bitangent * nmap2.y), nmap2.x));
                float3 finalNormal = normalize(normalize(normal1 + normal2) + normal * _NormalStrength);

                // Diffuse lighting
                float3 diffuseLight = _LightColor0.rgb * _BaseColor.rgb * _LightColor0.a;

                // Specular lighting
                float3 specularLight = _LightColor0.rgb * _Specular;

                // Ambient lighting
                float3 ambientLight = UNITY_LIGHTMODEL_AMBIENT.rgb * _BaseColor.rgb;

                // Calculate lighting contribution
                fixed4 finalColor = fixed4(0, 0, 0, 0);
                finalColor.rgb += finalColor.rgb * (_Subsurface * _SubsurfaceColor.rgb);
                finalColor.rgb += diffuseLight * _Metallic + ambientLight;
                finalColor.rgb += (specularLight * _SpecularTint + ambientLight) * _Roughness;

                // Apply sheen
                float3 sheenColor = _LightColor0.rgb * _Sheen * _SheenTint;
                finalColor.rgb += sheenColor;

                // Apply clearcoat
                float3 clearcoatColor = _LightColor0.rgb * _Clearcoat;
                finalColor.rgb += clearcoatColor;

                // Apply clearcoat gloss
                finalColor.rgb += clearcoatColor * _ClearcoatGloss;

                // Apply fog
                // ...

                return finalColor;
            }
            ENDCG
        }
    }
}



Shader "Custom/ManyBRDF"
    {
        Properties
        {
            _NormalTex1 ("Texture", 2D) = "white" {}
            _NormalTex2 ("Texture", 2D) = "white" {}
            _Cube("Reflection Map", Cube) = "" {}
            _NormalStrength("Bump strength", Float) = 0.2 
            _GratingFrequency("Grating frequency (over u tex coord)", Float) = 10.0
            _Roughness("Roughness", Float) = 0.5
            _SpecularColor("Specular Color", Color) = (2.0, 2.0, 2.0, 1.0)
            _Power("Ambient Occlusion Power", Range(0, 10)) = 1.0
            _Shininess("Shininess", Range(1, 128)) = 32.0
            _Albedo("Albedo", Color) = (1.0, 1.0, 1.0, 1.0)
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

            /* struct appdata_full {
                    float4 vertex : POSITION;
                    float4 tangent : TANGENT;
                    float3 normal : NORMAL;
                    float4 texcoord : TEXCOORD0;
                    UNITY_VERTEX_INPUT_INSTANCE_ID
                };*/

                sampler2D _NormalTex1;
                sampler2D _NormalTex2;
                samplerCUBE _Cube;
                float4 _NormalTex1_ST;
                float _NormalStrength;
                float _GratingFrequency;
                float _Roughness;
                float3 _SpecularColor; 
                float _Power;
                float _Shininess;
                float3 _Albedo;

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
                
                //Schlick approximation from http://graphicrants.blogspot.com.au/2013/08/specular-brdf-reference.html
                float3 F_Schlick(float3 specularColor, float cosTheta)
                {
                    return specularColor + (1.0 - specularColor) * pow(1.0 - cosTheta, 5.0);
                }
                    //Geometry Smith function from http://graphicrants.blogspot.com.au/2013/08/specular-brdf-reference.html
                float G_Smith(float3 normal, float3 viewDir, float3 lightDir, float roughness)
                {
                    float nDotV = max(dot(normal, viewDir), 0.0);
                    float nDotL = max(dot(normal, lightDir), 0.0);
                    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;

                    float gl = nDotV / (nDotV * (1.0 - k) + k);
                    float gv = nDotL / (nDotL * (1.0 - k) + k);

                    return gl * gv;
                }
                    //Disribution GGX function from http://graphicrants.blogspot.com.au/2013/08/specular-brdf-reference.html
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

                float CalculateAmbientOcclusion(float3 position, float3 normal)
                    {
                        float occlusion = 1.0;
                        
                        // Adjust the following parameters based on your scene and desired effect quality (higher values = lower quality)
                        float maxDistance = 0.1;
                        float samples = 16;
                        
                        for (float i = 0.0; i < samples; i++)
                        {
                            float angle = i * (2.0 * 3.14159) / samples;
                            float3 sampleDir = normalize(float3(cos(angle), sin(angle), 1.0));
                            float3 samplePos = position + sampleDir * maxDistance;
                            
                            float sampleDepth = texCUBE(_Cube, float4(samplePos, 1.0)).r;
                            float depth = dot(sampleDir, normal);
                            
                            occlusion -= smoothstep(0.0, 1.0, depth / sampleDepth);
                        }
                        
                        return exp2(_Power * log2(occlusion));
                    }

                float3 gratingNormal(float val, float3 n, float3 t)
                {
                    return normalize(t * val + n);
                }
    
                  // Oren-Nayar BRDF from http://www.thetenthplanet.de/archives/1180 (modified to use a roughness parameter) 
                //https://en.wikipedia.org/wiki/Oren%E2%80%93Nayar_reflectance_model

                float OrenNayarBRDF(float3 viewDir, float3 lightDir, float3 normal, float roughness, float albedo)
                {
                    float sigmaSquared = roughness * roughness;
                    float A = 1.0 - 0.5 * (sigmaSquared / (sigmaSquared + 0.57));
                    float B = 0.45 * (sigmaSquared / (sigmaSquared + 0.09));
                    float thetaView = acos(dot(viewDir, normal));
                    float thetaLight = acos(dot(lightDir, normal));
                    float alpha = max(thetaView, thetaLight);
                    float beta = min(thetaView, thetaLight);
                    float alphaSin = sin(alpha);
                    float betaTan = tan(beta);
                    return max(0.0, dot(normalize(lightDir - dot(lightDir, normal) * normal), normalize(viewDir - dot(viewDir, normal) * normal))) * (A + B * max(0.0, dot(viewDir, normal)) * max(0.0, dot(lightDir, normal)) * alphaSin * betaTan) * albedo;
                }


                float3 shade(float3 dir, float roughness, int Nsamples)
                {
                    
                    float4 t = float4(dir, roughness * 2.0);
                    return texCUBElod(_Cube, t).rgb;
                }

              

                fixed4 frag(v2f i) : SV_Target
                {


                    // Retrieve the specular color from the shader properties
                    float3 specularColor = _SpecularColor.rgb;   
                    //float4 specularColor = float4(_SpecularColor, 1.0); 
                    float shininess = _Shininess;
                    float3 albedo = _Albedo;

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
                    // Cook-Torrance Lighting
                    //

                    // float3 halfwayDir = normalize(lightdir + viewdir);
                    // float3 fresnelTerm = F_Schlick(specularColor, dot(halfwayDir, viewdir));
                    // float3 geometricTerm = G_Smith(normal, viewdir, lightdir, _Roughness);
                    // float3 distributionTerm = D_GGX(normal, halfwayDir, _Roughness);

                    // float3 specularTerm = (fresnelTerm * geometricTerm * distributionTerm) / (4.0 * max(dot(normal, viewdir), 0.001));


                    //Blinn-Phong
                    // float3 halfwayDir = normalize(lightdir + viewdir);
                    // float3 specularTerm = pow(max(dot(normal, halfwayDir), 0.0), shininess) * specularColor;

                    //Oren-Nayar
                    float3 specularTerm = OrenNayarBRDF(viewdir, lightdir, normal, _Roughness, albedo);


                    //--------------------------
                    // Grating
                    //

                    gvals g = gratingValue(i.uv);
                    float ndotv = dot(viewdir, normal);
                    float3 normal_grate = gratingNormal(g.grating, normal, tangent);
                    float3 normal_grate1 = normalize(clamp(g.grating, 0.0, 1.0) * normal_grate + normal1);
                    float3 normal_grate2 = normalize(clamp(1.0 - g.grating, 0.0, 1.0) * normal_grate + normal2);

                    int Nsamples = 128;

                    float3 reflectiondir1 = reflect(-viewdir, normal_grate1);
                    float3 reflectiondir2 = reflect(-viewdir, normal_grate2);
                    float3 envcolor1 = shade(reflectiondir1, _Roughness, Nsamples);
                    float3 envcolor2 = shade(reflectiondir2, _Roughness, Nsamples);

                    //--------------------------
                    // Far shading 
                    //

                    float3 reflectiondirDistant1 = normalize(reflect(-viewdir, normal1));
                    float3 reflectiondirDistant2 = normalize(reflect(-viewdir, normal2));
                    float3 envcolorDistant1 = shade(reflectiondirDistant1, _Roughness, Nsamples);
                    float3 envcolorDistant2 = shade(reflectiondirDistant2, _Roughness, Nsamples);

                    //--------------------------
                    // Blending
                    //
                    
                    // float distant_blending = 0.5 - 0.5 * dot(tangent, viewdir);
                    // float near_blending = 0.5 - 0.5 * g.grating;
                    
                    //usage of smoothstep instead of linear interpolation to avoid artifacts at the border of the grating (due to the grating being a cosine)
                    //float distant_blending = smoothstep(0.4, 0.6, 0.5 - 0.5 * dot(tangent, viewdir));
                    //float near_blending = smoothstep(0.4, 0.6, 0.5 - 0.5 * g.grating);
                    //float distant_blending = pow(0.5 - 0.5 * dot(tangent, viewdir), 2.0);
                    //float near_blending = pow(0.5 - 0.5 * g.grating, 2.0);
                    //blending based on the factor of the grating 
                    //float distant_blending = lerp(0.0, 1.0, smoothstep(0.4, 0.6, 0.5 - 0.5 * dot(tangent, viewdir)));
                    //float near_blending = lerp(0.0, 1.0, smoothstep(0.4, 0.6, 0.5 - 0.5 * g.grating));
                    float distant_blending = smoothstep(0.3, 0.7, 0.5 - 0.5 * dot(tangent, viewdir));
                    float near_blending = smoothstep(0.3, 0.7, 0.5 - 0.5 * g.grating);
                    float3 shadingNear = lerp(envcolor1, envcolor2, near_blending);
                    float3 shadingFar = lerp(envcolorDistant1, envcolorDistant2, distant_blending);

                    float3 envcolor = lerp(shadingNear, shadingFar, g.factor);

                    float ndotl = dot(lightdir, normal);
                    float3 shading = ndotl * lightcolor * envcolor;

                    float ambientOcclusion = CalculateAmbientOcclusion(i.vertex_wcs.xyz, i.normal_wcs);
                    float3 finalShading = ambientOcclusion * shading;

                    return fixed4(shading, 1.0);
                }
                ENDCG
            }
        }
    }






