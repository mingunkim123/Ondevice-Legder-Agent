// 경로: apps/api/src/index.ts
import { Hono } from 'hono';
import { cors } from 'hono/cors';

import transactionsRoute from './routes/transactions';
import summaryRoute from './routes/summary';

const app = new Hono<{ Bindings: { TURSO_DATABASE_URL: string; TURSO_AUTH_TOKEN: string; SUPABASE_JWT_SECRET: string }, Variables: { userId: string } }>();

// 1. 웹 브라우저나 스마트폰 등 외부에서 서버에 접근할 수 있게 허락해 주는 설정
app.use('/*', cors());

// 2. 서버가 잘 켜졌는지 확인하기 위한 헬스체크(생존 신고) 라우트
app.get('/api/health', (c) => c.json({ status: 'ok', timestamp: new Date().toISOString() }));

// 3. 방금 만든 두 개의 라우트 조음 (경로 단위로 묶어주기)
app.route('/api/transactions/summary', summaryRoute);
app.route('/api/transactions', transactionsRoute);

export default app;
