// 경로: apps/api/src/db/client.ts
import { createClient } from '@libsql/client/web';

export const createDbClient = (url: string, authToken: string) => {
    return createClient({
        url: url,
        authToken: authToken,
    });
};
