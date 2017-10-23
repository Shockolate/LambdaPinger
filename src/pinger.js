'use strict';

const pinger = require('tcp-ping');

function handler(event, context, callback) {
  // Event should be an object which may have these properties:
  // address (localhost)
  // port (80)
  // attempts (10)

  // const timeoutMillis = context.getRemainingTimeInMillis() - 10000;
  const options = {
    address: event.address,
    port: event.port,
    attempts: event.attempts,
    timeout: event.timeout,
  };

  console.log('Options:');
  console.log(JSON.stringify(options));

  pinger.ping(options, (error, data) => {
    if (error) {
      console.log(`Error pinging: ${error}`);
      return callback(error);
    }
    console.log(JSON.stringify(data));
    return callback(null, 'Successful ping.');
  });
}

module.exports = {
  handler,
};
