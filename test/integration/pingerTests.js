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

const databaseEventIp = {
  address: '10.50.129.111',
  attempts: 5,
  timeout: 250,
  port: 1433,
};

const databaseEventDns = {
  address: 'dbservices03.prd.irl.datamanagement.vpsvc.com',
  attempts: 5,
  timeout: 500,
  port: 1433,
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

    it('should return successfully with ETS Database via IP', () => (
      expect(handler(databaseEventIp, null)).to.be.fulfilled()
    )).timeout(12000);

    it('should return successfully with ETS Database via DNS', () => (
      expect(handler(databaseEventDns, null)).to.be.fulfilled()
    )).timeout(12000);
  });
});
