// 경로: apps/api/src/middleware/idempotency.ts
import type { Context, Next } from 'hono';

export const idempotencyMiddleware = async (c: Context, next: Next) => {
    // 1. 사용자 폰(앱) 쪽에서 보낸 고유 식별 도장(Idempotency-Key)이 있는지 확인
    const key = c.req.header('Idempotency-Key');
    if (!key) {
        return c.json({ error: 'Idempotency-Key header is required' }, 400);
    }

    // 2. 보내온 본문(body) 데이터를 읽어옴
    let body;
    try {
        body = await c.req.json();
    } catch (err) {
        return c.json({ error: 'Invalid JSON body' }, 400);
    }

    // 3. 본문의 고유 id와 헤더의 도장(key)값이 다르면 차단 (위조 방지)
    if (body.id !== key) {
        return c.json({ error: 'Idempotency-Key must match transaction id' }, 400);
    }

    await next();
};
