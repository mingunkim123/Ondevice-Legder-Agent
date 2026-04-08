// 경로: apps/api/src/routes/summary.ts
import { Hono } from 'hono';
import { createDbClient } from '../db/client';
import { authMiddleware } from '../middleware/auth';

const summary = new Hono<{ Bindings: { TURSO_DATABASE_URL: string; TURSO_AUTH_TOKEN: string; SUPABASE_JWT_SECRET: string }, Variables: { userId: string } }>();

summary.use('/*', authMiddleware);

summary.get('/', async (c) => {
    const userId = c.get('userId');
    const month = c.req.query('month');

    if (!month) {
        return c.json({ error: 'Month parameter is required (ex: 2024-04)' }, 400);
    }

    const db = createDbClient(c.env.TURSO_DATABASE_URL, c.env.TURSO_AUTH_TOKEN);

    try {
        // 분류(category_id)별로 그룹을 지어서 합산(SUM)하기
        const rs = await db.execute({
            sql: `SELECT category_id, SUM(amount) as amount, COUNT(*) as count 
            FROM transactions 
            WHERE user_id = ? AND date LIKE ? AND deleted_at IS NULL 
            GROUP BY category_id`,
            args: [userId, `${month}-%`]
        });

        // 전부 다 합친 전체 지출액 한 번에 구하기
        const totalRs = await db.execute({
            sql: `SELECT SUM(amount) as total 
            FROM transactions 
            WHERE user_id = ? AND date LIKE ? AND deleted_at IS NULL`,
            args: [userId, `${month}-%`]
        });

        const total = Number(totalRs.rows[0]?.total ?? 0);

        return c.json({
            month,
            total,
            by_category: rs.rows
        });
    } catch (error) {
        console.error('[GET /api/transactions/summary] Database Error:', error);
        return c.json({ error: 'Database error' }, 500);
    }
});

export default summary;
