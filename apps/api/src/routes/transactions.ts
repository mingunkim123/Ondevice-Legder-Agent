// 경로: apps/api/src/routes/transactions.ts
import { Hono } from 'hono';
import { createDbClient } from '../db/client';
import { createTransactionSchema } from '../validators/transaction';
import { authMiddleware } from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';

// 환경 변수(env) 타입 힌트를 제공하여 Hono 앱 생성
const transactions = new Hono<{ Bindings: { TURSO_DATABASE_URL: string; TURSO_AUTH_TOKEN: string; SUPABASE_JWT_SECRET: string }, Variables: { userId: string } }>();

// 1. 이 라우터로 들어오는 모든 요청은 무조건 '방문증(auth)' 검사를 거쳐야 함
transactions.use('/*', authMiddleware);

// 2. [지출 기록 추가 API] - POST / 
// (여기는 '따닥(중복)' 방지 미들웨어도 추가로 거칩니다)
transactions.post('/', idempotencyMiddleware, async (c) => {
    const body = await c.req.json(); // 앞에서 읽었었지만 Hono가 캐싱해두어 안전하게 다시 꺼냅니다.

    // Zod 거름망으로 들어온 데이터 검증
    const parsed = createTransactionSchema.safeParse(body);
    if (!parsed.success) {
        return c.json({ error: 'Invalid data', details: parsed.error }, 400);
    }
    const data = parsed.data;
    const userId = c.get('userId'); // 방문증 확인 시 달아둔 ID 꺼내기

    const db = createDbClient(c.env.TURSO_DATABASE_URL, c.env.TURSO_AUTH_TOKEN);

    try {
        // ON CONFLICT DO NOTHING: 같은 ID가 들어와도 에러 없이 무시
        const result = await db.execute({
            sql: `INSERT INTO transactions (id, user_id, amount, date, category_id, memo, raw_utterance, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING`,
            args: [data.id, userId, data.amount, data.date, data.category_id, data.memo ?? null, data.raw_utterance ?? null, data.source]
        });

        // 중복 요청: 실제로 insert되지 않은 경우 (rowsAffected = 0)
        if (result.rowsAffected === 0) {
            return c.json({ id: data.id, duplicate: true }, 200);
        }

        // 신규 insert 성공 시에만 감사 로그 기록
        await db.execute({
            sql: `INSERT INTO audit_logs (user_id, action, record_id, payload) VALUES (?, ?, ?, ?)`,
            args: [userId, 'insert', data.id, JSON.stringify(data)]
        });

        return c.json({ id: data.id, message: 'Transaction created' }, 201);
    } catch (error) {
        console.error('[POST /api/transactions] Database Error:', error);
        return c.json({ error: 'Database error' }, 500);
    }
});

// 3. [지출 목록 검색 및 조회 API] - GET /
transactions.get('/', async (c) => {
    const userId = c.get('userId');
    const month = c.req.query('month'); // URL 끝에 ?month=2024-04 달고 온 파라미터 확인

    const limit = Math.min(parseInt(c.req.query('limit') || '50', 10), 100);
    const page = Math.max(parseInt(c.req.query('page') || '1', 10), 1);
    const offset = (page - 1) * limit;

    const db = createDbClient(c.env.TURSO_DATABASE_URL, c.env.TURSO_AUTH_TOKEN);

    // 기본적으로 내 아이디의 기록이고 '삭제되지 않은(deleted_at IS NULL)' 것만 찾기
    let sql = `SELECT * FROM transactions WHERE user_id = ? AND deleted_at IS NULL`;
    let countSql = `SELECT COUNT(*) as total FROM transactions WHERE user_id = ? AND deleted_at IS NULL`;
    let args: any[] = [userId];

    if (month) {
        sql += ` AND date LIKE ?`;
        countSql += ` AND date LIKE ?`;
        args.push(`${month}-%`);
    }

    // 💡 [추가된 부분 3] 쿼리 끝에 정렬 및 LIMIT, OFFSET을 붙임
    sql += ` ORDER BY date DESC, created_at DESC LIMIT ? OFFSET ?`;

    try {
        // 💡 [추가된 부분 4] db.batch를 사용하여 두 쿼리를 한 번의 네트워크 통신으로 처리
        const [rs, countRs] = await db.batch([
            { sql, args: [...args, limit, offset] },
            { sql: countSql, args }
        ]);
        const totalItems = Number(countRs.rows[0].total);
        const totalPages = Math.ceil(totalItems / limit);
        // 결과와 함께 페이지네이션 메타데이터 응답
        return c.json({
            data: rs.rows,
            pagination: {
                page,
                limit,
                totalItems,
                totalPages,
                hasNextPage: page < totalPages
            }
        });
    } catch (error) {
        console.error('[GET /api/transactions] Database Error:', error);
        return c.json({ error: 'Database error' }, 500);
    }
});

// 4. [지출 내역 삭제 API] - DELETE /:id
transactions.delete('/:id', async (c) => {
    const userId = c.get('userId');
    const txId = c.req.param('id'); // 지울 대상의 ID

    const db = createDbClient(c.env.TURSO_DATABASE_URL, c.env.TURSO_AUTH_TOKEN);

    try {
        // 소프트 삭제: WHERE user_id = ? 조건이 다른 유저 데이터 보호
        const result = await db.execute({
            sql: `UPDATE transactions SET deleted_at = datetime('now'), updated_at = datetime('now') WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
            args: [txId, userId]
        });

        // 실제로 업데이트된 행이 없으면 → 존재하지 않거나 이미 삭제된 것
        if (result.rowsAffected === 0) {
            return c.json({ error: 'Transaction not found' }, 404);
        }

        await db.execute({
            sql: `INSERT INTO audit_logs (user_id, action, record_id) VALUES (?, ?, ?)`,
            args: [userId, 'soft_delete', txId]
        });

        return c.json({ message: 'Transaction deleted' });
    } catch (error) {
        console.error('[DELETE /api/transactions/:id] Database Error:', error);
        return c.json({ error: 'Database error' }, 500);
    }
});

export default transactions;
