// 경로: apps/api/src/validators/transaction.ts
import { z } from 'zod';

const VALID_CATEGORIES = [
    'food', 'cafe', 'transport', 'shopping',
    'health', 'culture', 'utility', 'etc'
] as const;

export const createTransactionSchema = z.object({
    id: z.string().uuid(), // 식별자는 규칙에 맞는 UUID여야 함
    amount: z.number().positive().max(100_000_000), // 최대 1억원으로 한도 제한
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), // YYYY-MM-DD 형식 강제
    category_id: z.enum(VALID_CATEGORIES),
    memo: z.string().max(200).optional(),
    raw_utterance: z.string().max(500).optional(),
    source: z.enum(['form', 'agent']), // 화면 입력인지, 챗봇 입력인지
});
