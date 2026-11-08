// The API's endpoints (docs/API.md "Endpoints"), the table the handler dispatches over. No
// imports: the lint gate reads it from supabase/checks to compare with docs/api/openapi.yaml.

export const routes = [
  { operation: 'listItems', method: 'GET', path: '/v1/items', scope: 'read', idempotent: false },
  { operation: 'addItems', method: 'POST', path: '/v1/items', scope: 'write', idempotent: true },
  { operation: 'getItem', method: 'GET', path: '/v1/items/{id}', scope: 'read', idempotent: false },
  {
    operation: 'moveItem',
    method: 'PATCH',
    path: '/v1/items/{id}',
    scope: 'write',
    idempotent: false,
  },
  {
    operation: 'tickItem',
    method: 'POST',
    path: '/v1/items/{id}/tick',
    scope: 'write',
    idempotent: true,
  },
  {
    operation: 'untickItem',
    method: 'POST',
    path: '/v1/items/{id}/untick',
    scope: 'write',
    idempotent: true,
  },
  {
    operation: 'listCategories',
    method: 'GET',
    path: '/v1/categories',
    scope: 'read',
    idempotent: false,
  },
  { operation: 'listStores', method: 'GET', path: '/v1/stores', scope: 'read', idempotent: false },
  { operation: 'listLists', method: 'GET', path: '/v1/lists', scope: 'read', idempotent: false },
] as const satisfies readonly {
  operation: string;
  method: 'GET' | 'POST' | 'PATCH';
  path: `/v1/${string}`;
  scope: 'read' | 'write';
  /** Takes an Idempotency-Key header. */
  idempotent: boolean;
}[];

export type Route = (typeof routes)[number];
export type Operation = Route['operation'];
export type Scope = Route['scope'];
