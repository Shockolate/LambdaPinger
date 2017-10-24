// TESTS pinger

'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
const dirtyChai = require('dirty-chai');
const api = require('../../src/pinger');
// const sinon = require('sinon');
const promisify = require('es6-promisify');

const expect = chai.expect;
chai.use(chaiAsPromised);
chai.use(dirtyChai);

const googleEvent = {
  address: 'google.com',
  attempts: 5,
  timeout: 10000,
};

describe('Pinger', () => {
  describe('handler', () => {
    let handler;
    before('Promisify handler.', () => {
      handler = promisify(api.handler);
    });

    it('should return successfully with google.', () => (
      expect(handler(googleEvent, null)).to.be.fulfilled()
    ));
  });
});
