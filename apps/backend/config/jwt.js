

const jwt = require('jsonwebtoken');
const debug = require('../utils/debug');

function signToken(user) {
  debug('JWT_SECRET exists:', !!process.env.JWT_SECRET);

  const payload = {
    sub: user.id,
    role: user.role,
  };

  const token = jwt.sign(payload, process.env.JWT_SECRET, {
    expiresIn: '1d',
  });

  return token;
}

module.exports = {
  signToken,
};
