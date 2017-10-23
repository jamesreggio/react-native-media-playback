import invariant from './invariant';

/**
 * FiniteStateMachine provides a state machine with serialized, asynchronous
 * state transitions.
 */

export default class FiniteStateMachine {
  constructor(states, initialState, context) {
    this.states = states;
    this.context = context;
    this.chain = Promise.resolve();
    this.setState(initialState);
  }

  /**
   * Advance to the next state via the given edge.
   *
   * Resolves with the value returned by the edge function.
   */

  async next(edge, ...args) {
    this.chain = this.chain.then(() => {
      const state = this.states[this.state];
      invariant(edge in state, `${edge} is not a valid edge`);
      const [nextState, value] = await state[edge].apply(this.context, args);
      this.setState(nextState);
      return value;
    });

    return await this.chain;
  }

  /**
   * Update the current state.
   */

  setState(name) {
    invariant(name in this.states, `${name} is not a valid state`);
    this.state = name;
  }
}
