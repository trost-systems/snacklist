// The API's endpoints (docs/API.md "Endpoints"), the table the handler dispatches over. No
// imports: the lint gate reads it from supabase/checks to compare with docs/api/openapi.yaml.

export const routes = [
  { operation: 'listItems', method: 'GET', path: '/v1/items', scope: 'read', idempotent: false },
  { operation: 'addItems', method: 'POST', path: '/v1/items', scope: 'write', idempotent: true },
  // Before /v1/items/{id}: the first route that fits a path and method wins.
  {
    operation: 'recentItems',
    method: 'GET',
    path: '/v1/items/recent',
    scope: 'read',
    idempotent: false,
  },
  { operation: 'getItem', method: 'GET', path: '/v1/items/{id}', scope: 'read', idempotent: false },
  {
    operation: 'updateItem',
    method: 'PATCH',
    path: '/v1/items/{id}',
    scope: 'write',
    idempotent: false,
  },
  {
    operation: 'deleteItem',
    method: 'DELETE',
    path: '/v1/items/{id}',
    scope: 'write',
    idempotent: true,
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
    operation: 'placeItem',
    method: 'POST',
    path: '/v1/items/{id}/place',
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
  { operation: 'addStore', method: 'POST', path: '/v1/stores', scope: 'write', idempotent: true },
  {
    operation: 'updateStore',
    method: 'PATCH',
    path: '/v1/stores/{id}',
    scope: 'write',
    idempotent: false,
  },
  {
    operation: 'getStoreLayout',
    method: 'GET',
    path: '/v1/stores/{id}/layout',
    scope: 'read',
    idempotent: false,
  },
  {
    operation: 'setStoreLayout',
    method: 'PUT',
    path: '/v1/stores/{id}/layout',
    scope: 'write',
    idempotent: false,
  },
  {
    operation: 'setStoreOrder',
    method: 'PUT',
    path: '/v1/stores/{id}/order',
    scope: 'write',
    idempotent: false,
  },
  { operation: 'listLists', method: 'GET', path: '/v1/lists', scope: 'read', idempotent: false },
  { operation: 'createList', method: 'POST', path: '/v1/lists', scope: 'write', idempotent: true },
  {
    operation: 'updateList',
    method: 'PATCH',
    path: '/v1/lists/{id}',
    scope: 'write',
    idempotent: false,
  },
  {
    operation: 'suggestItems',
    method: 'GET',
    path: '/v1/suggestions',
    scope: 'read',
    idempotent: false,
  },
  {
    operation: 'getHousehold',
    method: 'GET',
    path: '/v1/household',
    scope: 'read',
    idempotent: false,
  },
] as const satisfies readonly {
  operation: string;
  method: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
  path: `/v1/${string}`;
  scope: 'read' | 'write';
  /** Takes an Idempotency-Key header. */
  idempotent: boolean;
}[];

export type Route = (typeof routes)[number];
export type Operation = Route['operation'];
export type Scope = Route['scope'];
