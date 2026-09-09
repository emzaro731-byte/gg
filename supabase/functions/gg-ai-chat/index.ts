import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return new Response(JSON.stringify({ error: 'Missing authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  const groqKey = Deno.env.get('GROQ_API_KEY')
  if (!groqKey) return new Response(JSON.stringify({ error: 'GROQ_API_KEY is not configured in Supabase.' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  try {
    const body = await req.json()
    const input = Array.isArray(body?.messages) ? body.messages : []
    const messages = input
      .filter((m: any) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
      .slice(-30)
      .map((m: any) => ({ role: m.role, content: m.content.slice(0, 12000) }))

    if (!messages.length || messages[messages.length - 1].role !== 'user') {
      return new Response(JSON.stringify({ error: 'A user message is required.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const model = Deno.env.get('GROQ_MODEL') || 'llama-3.3-70b-versatile'
    const groqResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${groqKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: 'You are GG AI, the helpful AI assistant built into GG Messenger. Be friendly, concise, accurate, and useful.' },
          ...messages,
        ],
        temperature: 0.7,
        max_tokens: 2048,
      }),
    })

    const data = await groqResponse.json()
    if (!groqResponse.ok) {
      return new Response(JSON.stringify({ error: data?.error?.message || 'Groq request failed.' }), { status: groqResponse.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const reply = data?.choices?.[0]?.message?.content?.toString() || 'I could not generate a response.'
    return new Response(JSON.stringify({ reply, model }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unexpected server error.' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
