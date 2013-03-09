require 'heroku/bouncer'
require './app'

use Heroku::Bouncer, expose_token: true
run App