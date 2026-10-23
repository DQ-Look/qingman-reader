/**
 * 并发执行工具：限制并发数的任务池
 */
class PoolState<T> {
  items: T[] = [];
  nextIndex: number = 0;
  task: (item: T) => Promise<void> = (_item: T): Promise<void> => {
    return Promise.resolve();
  };
}

async function poolWorker<T>(state: PoolState<T>): Promise<void> {
  while (state.nextIndex < state.items.length) {
    const item: T = state.items[state.nextIndex];
    state.nextIndex++;
    await state.task(item);
  }
}

export async function runWithConcurrency<T>(
  items: T[],
  limit: number,
  task: (item: T) => Promise<void>
): Promise<void> {
  if (items.length === 0) {
    return;
  }
  const state: PoolState<T> = new PoolState<T>();
  state.items = items;
  state.task = task;
  const workerCount: number = Math.min(Math.max(1, limit), items.length);
  const workers: Promise<void>[] = [];
  for (let i = 0; i < workerCount; i++) {
    workers.push(poolWorker<T>(state));
  }
  await Promise.all(workers);
}
