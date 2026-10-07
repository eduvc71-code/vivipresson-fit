// ============================================================================
// VIVIPREFIT — Bunny Stream Signed Token Generator
// Supabase Edge Function (Deno Runtime)
// Genera tokens HLS firmados SHA256 con expiración de 120 minutos
// ============================================================================
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const BUNNY_STREAM_LIBRARY_ID = Deno.env.get("BUNNY_STREAM_LIBRARY_ID") ?? "";
const BUNNY_STREAM_API_KEY = Deno.env.get("BUNNY_STREAM_API_KEY") ?? "";
const BUNNY_STREAM_TOKEN_KEY = Deno.env.get("BUNNY_STREAM_TOKEN_KEY") ?? "";
const TOKEN_TTL_SECONDS = 7200; // 120 minutos

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing Bearer token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => ({}));
    const videoId: string | undefined = body?.videoId;
    if (!videoId) {
      return new Response(JSON.stringify({ error: "videoId required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verificar suscripción activa o admin
    const { data: profile, error: profileError } = await userClient
      .from("profiles")
      .select("plan_status, is_admin")
      .eq("id", userData.user.id)
      .maybeSingle();

    if (profileError || !profile) {
      return new Response(JSON.stringify({ error: "Profile not found" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const authorized =
      // Equivalente logico a la funcion SQL has_active_subscription():
      // Autoriza si el usuario es admin O tiene plan_status = 'active'
      profile.is_admin === true || profile.plan_status === "active";
    if (!authorized) {
      return new Response(
        JSON.stringify({ error: "Active subscription required" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generar token Bunny Stream
    const expires = Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS;
    const path = `/${videoId}/`;
    const tokenPayload = `${BUNNY_STREAM_TOKEN_KEY}${path}${expires}`;
    const token = await sha256Hex(tokenPayload);

    const embedUrl = `https://iframe.mediadelivery.net/embed/${BUNNY_STREAM_LIBRARY_ID}/${videoId}?token=${token}&expires=${expires}`;
    const hlsUrl = `https://vz-${BUNNY_STREAM_LIBRARY_ID}.b-cdn.net/${videoId}/playlist.m3u8?token=${token}&expires=${expires}`;

    return new Response(
      JSON.stringify({
        token,
        expires,
        expiresIn: TOKEN_TTL_SECONDS,
        embedUrl,
        hlsUrl,
        libraryId: BUNNY_STREAM_LIBRARY_ID,
        videoId,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("bunny-token error", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message || "Unknown error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});