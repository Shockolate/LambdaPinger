'use strict';

const pinger = require('tcp-ping');
const isEmpty = require('lodash.isempty');
const has = require('lodash.has');

// Event should be an object which may have these properties:
// address (localhost)
// port (80)
// attempts (10)
function handler(event, context, callback) {
  console.log(`Pinging: ${has(event, 'address') ? event.address : 'localhost'}`);
  console.log(`On Port: ${has(event, 'port') ? event.port : 80}`);
  console.log(`${has(event, 'attempts') ? event.attempts : 10} times.`);
  console.log(`With timeout: ${has(event, 'timeout') ? event.timeout : 5000}ms`);

  pinger.ping(event, (error, data) => {
    if (error) {
      console.log(`Error pinging: ${error}`);
      return callback(error);
    }
    let attempt;
    for (attempt of data.results) {
      if (has(attempt, 'err')) {
        console.log(`Attempt ${attempt.seq + 1} : ${isEmpty(attempt.err) ? 'Timed out' : attempt.err.code}.`);
      } else {
        console.log(`Attempt ${attempt.seq + 1} : ${attempt.time}ms.`);
      }
    }
    return callback(null, data);
  });
}

module.exports = {
  handler,
};
