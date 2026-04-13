// 경로: apps/api/src/middleware/auth.ts
import { jwtVerify, createRemoteJWKSet } from 'jose';
import type { Context, Next } from 'hono';

export const authMiddleware = async (c: Context, next: Next) => {
    // 1. 요청 헤더에서 인증 증명서(Bearer 토큰) 꺼내기
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
        return c.json({ error: 'Unauthorized: 인증 토큰이 없습니다.' }, 401);
    }

    const token = authHeader.slice(7);

    try {
        // 2. Supabase는 ES256(비대칭 암호화) 사용 → JWKS 엔드포인트에서 공개키로 검증
        const jwksUrl = new URL(`${c.env.SUPABASE_URL}/auth/v1/.well-known/jwks.json`);
        const JWKS = createRemoteJWKSet(jwksUrl);
        const { payload } = await jwtVerify(token, JWKS);

        // 3. 통과했다면 방문증(userId)을 달아주고 다음 구역으로 통과(next)시킴
        c.set('userId', payload.sub as string);
        await next();
    } catch (err) {
        console.error('[auth] JWT 검증 실패:', err instanceof Error ? err.message : err);
        return c.json({ error: 'Invalid token: 만료되거나 잘못된 증명서입니다.' }, 401);
    }
};
