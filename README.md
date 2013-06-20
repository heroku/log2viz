# log2viz

http://log2viz.herokuapp.com/

Realtime analysis of your Heroku app logs.

## Installing Locally

### Requirements

* Heroku Toolbelt (https://toolbelt.heroku.com/)
* Ruby 1.9.3
* bundler

### Get the code

Clone the repository and install the required gems.

```bash
$ git clone git@github.com:heroku/log2viz.git
$ cd log2viz
$ bundle install
$ cp .env.sample .env
```

### Set up OAuth

`log2viz` uses OAuth to obtain authorization to fetch your application’s logs using the Heroku API. To make this work, you have to register an OAuth client with Heroku. The easiest way to do this is on your [account page on the Heroku Dashboard](https://dashboard.heroku.com/account). Enter `http://localhost:5000/auth/heroku/callback` when prompted for a callback URL. The [OAuth developer doc](devcenter.heroku.com/articles/oauth?preview=1) has additional details on client creation and OAuth in general.

When registering the client you get an OAuth client id and secret. Add these as `HEROKU_ID` and `HEROKU_SECRET` environment variables to your application’s `.env`.

### Start the server

```bash
$ foreman start
```

And you’re done! Your app will be running at http://localhost:5000

## Running on Heroku

### Create an application

```bash
$ heroku create -a myviz
```

### Create a new OAuth client

Register a new OAuth client as described above, this time using the URL of your publicly running app for the callback, i.e. `https://myviz.herokuapp.com/auth/heroku/callback`.

And set the appropriate variables on your Heroku app:

```bash
$ heroku config:set HEROKU_ID=xxxxxxxx \
	HEROKU_SECRET=xxxxxx 
```

### Deploy

```bash
$ git push heroku master
```

Visit your app at https://myviz.herokuapp.com

## Meta

Released under the [MIT license](http://www.opensource.org/licenses/mit-license.php).
