---
title: 'Create React App with Node.js API server in Docker'
date: 2017-12-21 22:32:01
tags:
  - CRA
  - React
  - Redux
  - Node.js
  - Webpack
  - JS
  - Docker
  - CRA with SSR series
---

I'm starting a [series](https://vfeskov.com/tags/CRA-with-SSR-series/) dedicated to React Server Side Rendering. In this part I'm making minimal client and server apps with CRA, Redux and plain Node.js, that are capable of supporting Server Side Rendering in the future.

<!-- more -->

I'm going to make separate client and server apps. The client will request posts asynchronously from the server using REST API and then render them.

The project **will not** have SSR yet, but it will be based on best practices and cool patterns, so worth checking it out. [Next post](https://vfeskov.com/2017/12/22/Create-React-App-with-Server-Side-Rendering/) **with** SSR will be based on this too.

- [Source code for this part](https://github.com/vfeskov/cra-ssr/tree/part-1-setup)
- [Live project this series is based on](https://github.com/vfeskov/win-a-beer)

## Index

- [Root folder](#root-folder)
- [Client](#client)
  - [client/package.json](#client-package)
  - [client/src/index.js](#client-src-index)
  - [client/src/reducers/](#client-src-reducers)
  - [client/src/actions/](#client-src-actions)
  - [client/src/App.js](#client-src-app)
- [Server](#server)
  - [server/package.json](#server-package)
  - [server/webpack.config.js](#server-webpack)
  - [server/src/index.js](#server-src-index)
  - [server/src/middlewares.js](#server-src-middlewares)
  - [server/src/db.json](#server-src-db)
  - [server/src/util.js](#server-src-util)
- [Verifying that it all works](#verifying)
  - [Development mode](#verifying-dev)
  - [Production mode](#verifying-prod)
- [Bonus: Production docker image](#docker)

## <a id="root-folder"></a>Root folder

Root folder of my project will be called `cra-ssr` and inside it there will be `client` and `server` folders.

To create the root I run:
```bash
mkdir cra-ssr
cd cra-ssr
```

## <a id="client"></a>Client

Provided I'm inside the root folder, I create client with [create-react-app](https://github.com/facebookincubator/create-react-app):
```bash
npx create-react-app client
cd client
```
I'm going to need [redux](https://redux.js.org/), its [react bindings](https://redux.js.org/docs/basics/UsageWithReact.html) and [thunk middleware](https://github.com/gaearon/redux-thunk) for async calls:
```bash
npm install --save redux react-redux redux-thunk
```
### <a id="client-package"></a>client/package.json
In `package.json` I need to:
1. rename the package
2. setup development proxy to point to my server on port `3001`
3. change `build` script to move `build` folder to `server`

```json
{
  "name": "cra-ssr-client",
  "proxy": "http://localhost:3001",
  "scripts": {
    "build": "react-scripts build && npm run move-build-to-server",
    "move-build-to-server": "mv build _build && mv _build ../server && cd ../server && rm -rf public && mv _build public",
  ...
}
```
### <a id="client-src-index"></a>client/src/index.js
First I add redux:
```jsx
// client/src/index.js
import React from 'react'
import ReactDOM from 'react-dom'
import './index.css'
import App from './App'
import registerServiceWorker from './registerServiceWorker'
import thunkMiddleware from 'redux-thunk'
import { Provider } from 'react-redux'
import { createStore, applyMiddleware } from 'redux'
import { root } from './reducers'

const store = createStore(root, applyMiddleware(thunkMiddleware))

ReactDOM.render(
  <Provider store={store}>
    <App />
  </Provider>,
  document.getElementById('root')
)

registerServiceWorker()
```

### <a id="client-src-reducers"></a>client/src/reducers/

Next I create root reducer:
```jsx
// client/src/reducers/index.js
import { combineReducers } from 'redux'
import { posts } from './posts'

export const root = combineReducers({
  posts
})
```
`posts` reducer handles state of posts that are loaded asynchronously, I create it in `src/reducers/posts.js`:
```jsx
// client/src/reducers/posts.js
import { RECEIVE_POSTS, ERROR_POSTS } from '../actions'

export function posts (state = [], action) {
  switch (action.type) {
    case RECEIVE_POSTS:
      return [...action.posts]
    case ERROR_POSTS:
      return []
    default:
      return state
  }
}
```

### <a id="client-src-actions"></a>client/src/actions/

Next I create redux actions:
```jsx
// client/src/actions/index.js
export * from './posts'
```
```jsx
// client/src/actions/posts.js
export const REQUEST_POSTS = 'REQUEST_POSTS'
export const RECEIVE_POSTS = 'RECEIVE_POSTS'
export const ERROR_POSTS = 'ERROR_POSTS'

export function requestPosts () {
  return {
    type: REQUEST_POSTS
  }
}

export function receivePosts (posts) {
  return {
    type: RECEIVE_POSTS,
    posts
  }
}

export function errorPosts () {
  return {
    type: ERROR_POSTS
  }
}

export function fetchPosts () {
  return dispatch => {
    return fetch('/api/posts')
      .then(response => {
        if (response.status === 200) {
          return response.json()
        }
        throw new Error(response.statusText)
      })
      .then(
        posts => dispatch(receivePosts(posts)),
        () => dispatch(errorPosts())
      )
  }
}
```
### <a id="client-src-app"></a>client/src/App.js

Finally I update App.js making exported `App` a redux container and `AppComponent` a presentational component inside it:

```jsx
import React, { Component } from 'react'
import * as actionCreators from './actions'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'

export class AppComponent extends Component {
  render () {
    return (
      <div className="App">
        {this.props.posts.map(post =>
          <div className="post" key={post.id}>
            <h1>{post.title}</h1>
            <p>{post.excerpt}</p>
          </div>
        )}
      </div>
    )
  }

  componentDidMount () {
    this.props.fetchPosts()
  }
}

export const App = connect(
  state => ({ posts: state.posts }),
  dispatch => bindActionCreators(actionCreators, dispatch)
)(AppComponent)

export default App
```

## <a id="server"></a>Server

Now I need a server. I go back to root `cra-ssr` folder and create `server` folder in it:
```bash
cd ..
mkdir server
cd server
```

### <a id="server-package"></a>server/package.json

My server will be compiled with webpack and it will have scripts to run in either production or development modes.

To do that I create the following `package.json`:

```json
{
  "name": "cra-ssr-server",
  "version": "1.0.0",
  "description": "",
  "main": "build/index.js",
  "scripts": {
    "build": "NODE_ENV=production webpack",
    "start": "NODE_ENV=production node build/index",
    "watch": "NODE_ENV=development PORT=3001 concurrently \"webpack --watch\" \"nodemon --watch build/index.js build/index.js\""
  },
  "dependencies": {
    "finalhandler": "^1.1.0",
    "serve-static": "^1.13.1"
  },
  "devDependencies": {
    "concurrently": "^3.5.1",
    "json-loader": "^0.5.7",
    "nodemon": "^1.14.0",
    "webpack": "^3.10.0",
    "webpack-node-externals": "^1.6.0"
  }
}
```

Then I run
```bash
npm install
```

### <a id="server-webpack"></a>server/webpack.config.js

In my webpack config I need a `.json` loader for my db and also I need to use `webpack.DefinePlugin` to make sure my production middlewares aren't imported in development:

```js
// server/webpack.config.js
const path = require('path')
const nodeExternals = require('webpack-node-externals')
const { DefinePlugin } = require('webpack')

const config = {
  target: 'node',
  entry: './index',
  context: path.resolve(__dirname, 'src'),
  output: {
    filename: 'index.js',
    path: path.join(__dirname, 'build')
  },
  module: {
    loaders: [
      { test: /\.json$/, loader: 'json-loader' }
    ]
  },
  plugins: [
    new DefinePlugin({
      'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV)
    })
  ],
  resolve: { extensions: ['.js', '.json'] }
}

config.externals = [nodeExternals()]

module.exports = config
```

### <a id="server-src-index"></a>server/src/index.js

In development mode the server will only serve `/api` requests and respond with error otherwise.

In production it will additionally serve static files from `server/public` folder of the project:

```jsx
// server/src/index.js
import http from 'http'
import { api, error } from './middlewares'
import { chain } from './util'

const envSpecificMiddlewares = []

if (process.env.NODE_ENV === 'production') {
  const serveStatic = require('serve-static')

  envSpecificMiddlewares.push(
    serveStatic('public')
  )
}

const middlewares = [
  api,
  ...envSpecificMiddlewares,
  error
]

const server = http.createServer(chain(middlewares))

server.listen(process.env.PORT || 3000)
```
Because of `webpack.DefinePlugin` the `if` closure will be completely omitted in development environment.

### <a id="server-src-middlewares"></a>server/src/middlewares.js
`api` middleware responds to `GET /api/posts` requests serving contents of `src/db.json` file, other requests it will pass to the next middleware.

`error` middleware simply responds with an http error.
```jsx
// server/src/middlewares.js
import db from './db.json'
import fs from 'fs'
import finalhandler from 'finalhandler'

export function api ({ method, url }, res, next) {
  if (method !== 'GET' || url !== '/api/posts') { return next() }
  res.writeHead(200, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(db))
}

export function error (req, res, next, err) {
  return finalhandler(req, res)(err)
}
```

### <a id="server-src-db"></a>server/src/db.json

```json
[
  {
    "id": 1,
    "title": "Bitoin's worth a lot",
    "excerpt": "Today bitcoin peaked at 9001k US dollars. That's a lot."
  },
  {
    "id": 2,
    "title": "Scientists invented new pants",
    "excerpt": "They're blue but, like, different kind of blue."
  }
]
```

### <a id="server-src-util"></a>server/src/util.js

I add a utility function to chain middlewares so that each middleware could pass handling to the next one if it can't respond to the request.

When any of the middlewares calls `next(err)` the error gets passed directly to the final middleware, skipping others:

```jsx
// server/src/util.js
export function chain (middlewares) {
  return (req, res) => {
    [...middlewares] // need to copy array because #reverse mutates it
      .reverse()
      .reduce(
        (next, middleware) => {
          return err => {
            // if next was called with an err, skip all middlewares and call the final one, whose next is null
            if (err && next) { return next(err) }
            middleware(req, res, next, err)
          }
        },
        null
      )()
  }
}
```

## <a id="verifying"></a>Verifying that it all works

### <a id="verifying-dev"></a>Development mode

In `client` folder I run:
```bash
npm start
```
Then I open another terminal and in `server` folder run:
```bash
npm run watch
```
On http://localhost:3000 I see my posts as expected.

### <a id="verifying-prod"></a>Production mode

In `client` folder I run:
```bash
npm run build
```
Then in `server` folder I run:
```bash
npm run build
npm start
```
On http://localhost:3000 I see my posts as expected.

## <a id="docker"></a>Bonus: Production docker image

I add `Dockerfile` in the root `cra-ssr` folder:

```dockerfile
FROM node:8.9.1-alpine

RUN mkdir -p /usr/src/app/server

WORKDIR /usr/src/app
ADD ./client ./client
ADD ./server ./server

RUN cd client && \
    npm install && \
    npm run build && \
    cd .. &&\
    \
    cd server && \
    npm install && \
    npm run build && \
    npm prune --production && \
    \
    rm -rf ../client

WORKDIR /usr/src/app/server

CMD [ "npm", "start" ]

EXPOSE 3000
```

I also create `.dockerignore` file next to `Dockerfile`:
```dockerignore
*/.env
*/build
*/node_modules
server/public
```
To build the image I run the following in `cra-ssr` folder:
```bash
docker build -t cra-ssr .
```
Now I run this image:
```bash
docker run -it --rm -p 3000:3000 cra-ssr
```
On http://localhost:3000 I see posts as expected.


----------

In the [next part](https://vfeskov.com/2017/12/22/Create-React-App-with-Server-Side-Rendering/) I will enable Service Side Rendering, [check it out](https://vfeskov.com/2017/12/22/Create-React-App-with-Server-Side-Rendering/).
