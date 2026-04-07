// 경로: apps/api/src/middleware/auth.ts
import { jwtVerify } from 'jose';
import type { Context, Next } from 'hono';

export const authMiddleware = async (c: Context, next: Next) => {
    // 1. 요청 헤더에서 인증 증명서(Bearer 토큰) 꺼내기
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
        return c.json({ error: 'Unauthorized: 인증 토큰이 없습니다.' }, 401);
    }

    const token = authHeader.slice(7);

    try {
        // 2. Cloudflare 환경 변수(env)에서 시크릿 비밀번호를 꺼내 증명서 위조 확인
        const secret = new TextEncoder().encode(c.env.SUPABASE_JWT_SECRET as string);
        const { payload } = await jwtVerify(token, secret);

        // 3. 통과했다면 방문증(userId)을 달아주고 다음 구역으로 통과(next)시킴
        c.set('userId', payload.sub as string);
        await next();
    } catch (err) {
        return c.json({ error: 'Invalid token: 만료되거나 잘못된 증명서입니다.' }, 401);
    }
};
