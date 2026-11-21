// Today and the five options as records: how a store is ordered (`kind`, model.js orderOf), what sits between rows
// (`heads`, `gaps`), how a wrong place is fixed (`fix`), and the extra controls (`sortButton`, `settings`).
// fix: 'category' (the edit sheet's category chip), 'none' (it learns from trips), 'drag' (a sort mode),
// 'nextTo' (the edit sheet's „Next to …“ chip), 'step' (Move up / Move down in the edit sheet).
export const options = {
  today: { id: 'today', kind: 'categorical', heads: () => true, fix: 'category' },
  IO1: { id: 'IO1', kind: 'categorical', heads: () => false, fix: 'category' },
  IO2: { id: 'IO2', kind: 'learned', heads: () => false, fix: 'none' },
  IO3: { id: 'IO3', kind: 'manual', heads: () => false, fix: 'drag', sortButton: true },
  IO4: { id: 'IO4', kind: 'learned', heads: () => false, fix: 'nextTo' },
  IO5: { id: 'IO5', kind: 'categorical', heads: (s) => s.showCats, gaps: (s) => !s.showCats, fix: 'step', settings: true },
};
export const ids = ['IO1', 'IO2', 'IO3', 'IO4', 'IO5'];
