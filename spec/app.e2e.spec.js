// End-to-end test for the todo app.
//
// Boots the real Express app wired to the real SQLite persistence layer
// on an ephemeral port, then exercises the actual HTTP routes:
//   POST /items, GET /items, PUT /items/:id, DELETE /items/:id
//
// No mocks. If this passes, the app genuinely works.

const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const express = require('express');

// Use a throwaway DB file per test run so we don't touch /etc/todos
// and don't collide with the existing sqlite.spec.js fixture.
const TMP_DB = path.join(
    os.tmpdir(),
    `todo-e2e-${process.pid}-${Date.now()}.db`,
);
process.env.SQLITE_DB_LOCATION = TMP_DB;
process.env.NODE_ENV = 'test';

const db = require('../src/persistence');
const getItems = require('../src/routes/getItems');
const addItem = require('../src/routes/addItem');
const updateItem = require('../src/routes/updateItem');
const deleteItem = require('../src/routes/deleteItem');

let server;
let baseUrl;

beforeAll(async () => {
    await db.init();

    const app = express();
    app.use(express.json());
    app.get('/items', getItems);
    app.post('/items', addItem);
    app.put('/items/:id', updateItem);
    app.delete('/items/:id', deleteItem);

    await new Promise(resolve => {
        server = app.listen(0, '127.0.0.1', resolve);
    });
    const { port } = server.address();
    baseUrl = `http://127.0.0.1:${port}`;
});

afterAll(async () => {
    await new Promise(resolve => server.close(resolve));
    await db.teardown();
    if (fs.existsSync(TMP_DB)) fs.unlinkSync(TMP_DB);
});

// Minimal HTTP helper so we don't pull in a new dependency.
function request(method, pathname, body) {
    return new Promise((resolve, reject) => {
        const data = body ? JSON.stringify(body) : null;
        const req = http.request(
            `${baseUrl}${pathname}`,
            {
                method,
                headers: {
                    'Content-Type': 'application/json',
                    ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}),
                },
            },
            res => {
                let raw = '';
                res.on('data', chunk => (raw += chunk));
                res.on('end', () => {
                    let parsed = raw;
                    try { parsed = raw ? JSON.parse(raw) : ''; } catch (_) {}
                    resolve({ status: res.statusCode, body: parsed });
                });
            },
        );
        req.on('error', reject);
        if (data) req.write(data);
        req.end();
    });
}

describe('todo app (HTTP)', () => {
    test('starts with an empty item list', async () => {
        const res = await request('GET', '/items');
        expect(res.status).toBe(200);
        expect(res.body).toEqual([]);
    });

    test('creates, lists, updates and deletes a todo', async () => {
        // Create
        const created = await request('POST', '/items', { name: 'write real tests' });
        expect(created.status).toBe(200);
        expect(created.body).toEqual({
            id: expect.any(String),
            name: 'write real tests',
            completed: false,
        });
        const id = created.body.id;

        // List contains the new item
        const listed = await request('GET', '/items');
        expect(listed.status).toBe(200);
        expect(listed.body).toContainEqual(created.body);

        // Update: mark completed
        const updated = await request('PUT', `/items/${id}`, {
            name: 'write real tests',
            completed: true,
        });
        expect(updated.status).toBe(200);
        expect(updated.body).toEqual({
            id,
            name: 'write real tests',
            completed: true,
        });

        // Delete
        const removed = await request('DELETE', `/items/${id}`);
        expect(removed.status).toBe(200);

        // Verify gone
        const after = await request('GET', '/items');
        expect(after.body.find(i => i.id === id)).toBeUndefined();
    });
});
