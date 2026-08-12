const defaultOrigins = [
  'https://charry-mary-store.vercel.app',
  'http://127.0.0.1:4321',
  'http://localhost:4321',
];

function allowedOrigins(): Set<string> {
  const configured = Deno.env.get('STRIPE_ALLOWED_ORIGINS')
    ?.split(',')
    .map((origin) => origin.trim())
    .filter(Boolean) ?? [];
  return new Set([...defaultOrigins, ...configured]);
}

export function corsHeaders(request: Request): HeadersInit | null {
  const origin = request.headers.get('origin');
  if (!origin || !allowedOrigins().has(origin)) return null;
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

export function jsonResponse(
  request: Request,
  body: Record<string, unknown>,
  status = 200,
): Response {
  const cors = corsHeaders(request);
  return Response.json(body, {
    status,
    headers: cors ?? {},
  });
}

export function requireBrowserOrigin(request: Request): HeadersInit {
  const cors = corsHeaders(request);
  if (!cors) throw new Error('Origin is not allowed');
  return cors;
}
