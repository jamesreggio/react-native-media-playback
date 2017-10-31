/**
 * Throw if the specified condition is not met.
 */

export default (condition, message) => {
  if (!condition) {
    throw Error(message || 'Invariant failed');
  }
};
