let token: string | null = null;
let unauthorized: (() => void) | null = null;
export function setSession(value: string | null, onUnauthorized?: () => void) {
  token = value;
  unauthorized = onUnauthorized ?? null;
}
export async function api<T>(
  path: string,
  options: { method?: string; body?: unknown; signal?: AbortSignal } = {},
): Promise<T> {
  const current = token;
  const response = await fetch(`/api/v1/admin${path}`, {
    method: options.method ?? "GET",
    signal: options.signal
      ? AbortSignal.any([options.signal, AbortSignal.timeout(45000)])
      : AbortSignal.timeout(45000),
    cache: "no-store",
    headers: {
      "Content-Type": "application/json",
      ...(current ? { Authorization: `Bearer ${current}` } : {}),
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) {
    if (
      (response.status === 401 || response.status === 403) &&
      current === token &&
      path !== "/auth/login"
    )
      unauthorized?.();
    const detail = body?.detail;
    throw new Error(
      typeof detail === "string"
        ? detail
        : Array.isArray(detail)
          ? detail.map((d: { msg: string }) => d.msg).join("; ")
          : `Request failed (${response.status}). Please retry.`,
    );
  }
  return body as T;
}

export function trackingToken() { return token; }
