import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
const GROQ_MODEL = Deno.env.get("GROQ_MODEL") || "openai/gpt-oss-120b";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function text(value: unknown, max = 12000): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function modeInstruction(mode: string): string {
  const instructions: Record<string, string> = {
    Chat: "Act as a versatile general-purpose assistant.",
    Code: "Act as an expert software engineer. Prefer correct, complete, runnable solutions and explain important errors or trade-offs.",
    Study: "Act as a patient tutor. Teach progressively, use examples and make difficult topics easy to understand.",
    Write: "Act as a professional writing assistant. Produce polished, usable text and match the requested audience and tone.",
    Creative: "Act as a creative partner. Generate original ideas and polished creative content.",
  };
  return instructions[mode] || instructions.Chat;
}

const BASE_SYSTEM_PROMPT = `
You are GG AI, the intelligent AI assistant built into GG Messenger.
You are powered by Groq.

Core behavior:
- Give accurate, useful and natural answers.
- Understand conversation context.
- Help with programming, mathematics, science, writing, business, education, technology and creative work.
- For code, provide complete practical solutions and important implementation details.
- Never claim to have performed an action you did not perform.
- Never invent sources, facts, links, tool results or capabilities.
- If information may be outdated or uncertain, say so clearly.
- Be concise for simple questions and detailed for complex requests.
- Use Markdown, headings, bullets, tables and code blocks when useful.
- You are GG AI, not ChatGPT. Do not claim to be the ChatGPT app or OpenAI itself.
`;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Only POST requests are supported." }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return jsonResponse({ error: "Authentication required." }, 401);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return jsonResponse({ error: "Supabase authentication is not configured." }, 500);
  if (!GROQ_API_KEY) return jsonResponse({ error: "GROQ_API_KEY is not configured in Supabase Function Secrets." }, 503);

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Invalid or expired session." }, 401);

    const body = await req.json();
    let input = Array.isArray(body?.messages) ? body.messages : [];
    if (input.length === 0 && typeof body?.message === "string" && body.message.trim()) {
      input = [{ role: "user", content: body.message.trim() }];
    }

    const messages = input
      .filter((m: any) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
      .slice(-80)
      .map((m: any) => ({ role: m.role, content: text(m.content, 24000) }))
      .filter((m: any) => m.content.length > 0);

    if (!messages.length) return jsonResponse({ error: "No valid messages were provided." }, 400);

    const mode = text(body?.mode, 80) || "Chat";
    const project = text(body?.project, 200);
    const context = text(body?.context, 10000);
    const systemParts = [
      BASE_SYSTEM_PROMPT,
      `Current mode: ${mode}. ${modeInstruction(mode)}`,
      project ? `Active project: ${project}. Keep relevant answers aligned with this project.` : "",
      context ? `Additional trusted app context:\n${context}` : "",
    ].filter(Boolean);

    const selectedModel = text(body?.model, 120) || GROQ_MODEL;
    const temperature = typeof body?.temperature === "number"
      ? Math.min(Math.max(body.temperature, 0), 2)
      : 0.7;
    const maxTokens = typeof body?.max_tokens === "number"
      ? Math.min(Math.max(body.max_tokens, 256), 16384)
      : 8192;

    const groqResponse = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${GROQ_API_KEY}`,
      },
      body: JSON.stringify({
        model: selectedModel,
        messages: [{ role: "system", content: systemParts.join("\n\n") }, ...messages],
        temperature,
        max_tokens: maxTokens,
      }),
    });

    const raw = await groqResponse.text();
    let data: any = null;
    try { data = JSON.parse(raw); } catch (_) {}

    if (!groqResponse.ok) {
      const message = data?.error?.message || raw || `Groq API returned HTTP ${groqResponse.status}.`;
      console.error("Groq API error:", groqResponse.status, message);
      return jsonResponse({ error: message, status: groqResponse.status }, groqResponse.status);
    }

    const reply = data?.choices?.[0]?.message?.content?.toString().trim();
    if (!reply) return jsonResponse({ error: "GG AI returned an empty response." }, 502);

    return jsonResponse({
      reply,
      model: selectedModel,
      provider: "groq",
      user_id: user.id,
      usage: data?.usage ?? null,
    });
  } catch (error) {
    console.error("GG AI function error:", error);
    return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected server error." }, 500);
  }
});
