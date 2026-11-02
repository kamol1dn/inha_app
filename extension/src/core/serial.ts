/**
 * A queue that runs tasks one at a time, in the order asked. Storage has no
 * transactions, so a read-modify-write of one key goes through one of these;
 * a task that fails doesn't stop the next.
 */
export function serial(): <T>(task: () => Promise<T>) => Promise<T> {
  let tail: Promise<unknown> = Promise.resolve();
  return (task) => {
    const run = tail.then(task);
    tail = run.catch(() => {});
    return run;
  };
}
