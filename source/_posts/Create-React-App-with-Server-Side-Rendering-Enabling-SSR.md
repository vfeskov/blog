---
title: 'Create React App with Server Side Rendering: Enabling SSR'
date: 2017-12-22 20:01:44
tags:
  - CRA
  - SSR
  - React
  - Redux
  - NodeJS
  - Webpack
  - Babel
  - JS
  - Docker
  - Service Worker
  - CRA with SSR series
---

I'm going to enable SSR in the minimal project I built in the [previous part](https://vfeskov.com/2017/12/21/Create-React-App-with-Server-Side-Rendering-Setup/) of the series dedicated to React Server Side Rendering.

<!-- more -->

- [Source code for this part](https://github.com/vfeskov/cra-ssr/tree/part-2-enabling-ssr).
- [Commit that adds SSR to the previous part](https://github.com/vfeskov/cra-ssr/commit/23857538863ead01c1a111b4426bb83ab558cb76).

Short recap:

- My project consists of `client` and `server` folders
- `client` holds an app built with [create-react-app](https://github.com/facebookincubator/create-react-app)
- `client` app requests `/api/posts` from server asynchronously and displays them
- `build` script of `client` additionally moves generated `build` folder to `server`
- `server` has a NodeJS app that serves `/api/posts` requests with db content
- In production env `server` also serves `client`'s `build` folder as static files

## Index

- [Idea](#idea)
- [Client](#client)
  - [package.json](#client-package)
  - [src/reducers/](#client-src-reducers)
  - [src/App.js](#client-src-app)
  - [src/index.js](#client-src-index)
  - [src/renderServerSide.js](#client-src-renderserverside)
- [Server](#server)
  - [package.json](#server-package)
  - [src/index.js](#server-src-index)
  - [src/prodHandlers.js](#server-src-prodhandlers)
  - [webpack.config.js](#server-webpack)
- [Verifying that it all works](#verifying)
- [Caching problem](#caching-problem)

## <a id="idea"></a>Idea

My app displays posts when `receivePosts()` action gets dispatched, which in turn happens when app receives posts from the server asynchronously.

I will create a Redux store on the server side and dispatch this action to it, then I'll use the result state to render the client app server side.

I will also need to not fetch posts on the client if they were put in store on the server, I will do it with an extra reducer.

My server will import client files, to smoothen development I will use [webpack define plugin](https://webpack.js.org/plugins/define-plugin/) to import them only in production.

## <a id="client"></a>Client

### <a id="client-package"></a>package.json

First I'm going to modify build script to not only move `build` folder to `server`, but also rename `index.html` to `layout.html`, because we will render `index.html` dynamically:
```json
{
  "scripts": {
    "move-build-to-server": "mv build _build && mv _build ../server && cd ../server && rm -rf public && mv _build public && mv public/index.html public/layout.html",
    ...
}
```

### <a id="client-src-reducers"></a>src/reducers/

Next I'm going to add a reducer `inited`, which will produce boolean value: `false` by default and `true` when any kind of response is received for initial posts fetching.

```jsx
// src/reducers/inited.js
import { RECEIVE_POSTS, ERROR_POSTS } from '../actions'

export function inited (state = false, action) {
  switch (action.type) {
    case RECEIVE_POSTS:
    case ERROR_POSTS:
      return true
    default:
      return state
  }
}
```

```jsx
// src/reducers/index.js
...
import { inited } from './inited'

export const root = combineReducers({
  posts,
  inited
})
```
When I dispatch posts server side, `inited` value in store will become `true` and the client will know not to fetch posts again.

### <a id="client-src-app"></a>src/App.js

Now I'm going to make my App check for `inited` flag before fetching posts:

```jsx
// src/App.js
...
export class AppComponent extends Component {
  componentDidMount () {
    const { inited, fetchPosts } = this.props
    if (!inited) { fetchPosts() }
  }
  ...
}

export const App = connect(
  state => ({
    posts: state.posts,
    inited: state.inited
  }),
  dispatch => bindActionCreators(actionCreators, dispatch)
)(AppComponent)
```
`componentDidMount` hook never gets called on server side (by `renderToString`) making it perfect for such functionality.

### <a id="client-src-index"></a>src/index.js

Next I'll read initial state of Redux store from a global variable, which the server will add to `index.html`.

I will also unregister service worker to let visitors receive latest posts as soon as they get added to the DB - just like it worked before SSR. More on this [here](#caching-problem).

```jsx
// src/index.js
...
import { unregister } from './registerServiceWorker'
...
const initState = window.__INIT_STATE__ && JSON.parse(window.__INIT_STATE__)

const store = createStore(root, initState, applyMiddleware(thunkMiddleware))
...
unregister()
```

### <a id="client-src-renderserverside"></a>src/renderServerSide.js

Finally, I'm going to add `renderServerSide` function that will never be called by the client, but it will be imported by the server. The file will import Redux and other libs from the client, so it makes sense to put it here:

```jsx
// src/renderServerSide.js
import React from 'react'
import { createStore } from 'redux'
import { root } from './reducers'
import { receivePosts, errorPosts } from './actions'
import { Provider } from 'react-redux'
import { renderToString } from 'react-dom/server'
import { App } from './App'

export function renderServerSide (posts) {
  const store = createStore(root)
  store.dispatch(
    posts ? receivePosts(posts) : errorPosts()
  )

  const html = renderToString(
    <Provider store={store}>
      <App />
    </Provider>
  )
  const state = JSON.stringify(JSON.stringify(store.getState()))

  return { html, state }
}
```
`renderServerSide` accepts posts that the server will provide, and it will return `html` and `state` strings that the server will embed into `index.html`.

## <a id="server"></a>Server

### <a id="server-package"></a>package.json

I'm going to import client files in my server, and for that I need a few more packages to use with webpack:
```bash
npm install --save react babel-core
npm install --save-dev babel-loader babel-preset-react-app
```
Notice that `react` and `babel-core` are production dependencies, because some of **their** dependencies are required in runtime.

I couldn't pinpoint exactly which dependencies are needed because they were too many + it's not worth it in context of a server app anyway.

### <a id="server-src-index"></a>src/index.js

I'm going to change how environment-specific handlers are made, so that production handlers are never imported when I develop my API server.

Also I'm going to add a new request handler `index`, that will catch all `GET` requests that were skipped by the static server. It will serve `index.html` with prerendered client.

```jsx
// src/index.js
import http from 'http'
import { api, error } from './handlers'
import { chain } from './util'

const envSpecificHandlers = []

if (process.env.NODE_ENV === 'production') {
  const { staticFiles, index } = require('./prodHandlers')

  envSpecificHandlers.push(
    staticFiles('./public'),
    index()
  )
}

const handlers = [
  api,
  ...envSpecificHandlers,
  error
]

const server = http.createServer(chain(handlers))

server.listen(process.env.PORT || 3000)
```
Later I will use `webpack.DefinePlugin` to make webpack omit the if closure in development environment.

### <a id="server-src-prodhandlers"></a>src/prodHandlers.js

Here I'm going to import `serve-static` for the static server and I'll declare `index` handler that will prerender `index.html` with my client app.

In `index` handler I call `renderServerSide` function imported from client with posts I get from the db. The result app's `html` and `state` strings I put in corresponding places in the layout and respond with the result.

```jsx
// src/prodHandlers.js
import serveStatic from 'serve-static'
import fs from 'fs'
import db from './db.json'
import { renderServerSide } from '../../client/src/renderServerSide'

export function staticFiles (dir) {
  return serveStatic(dir)
}

export function index() {
  const layout = fs.readFileSync('./public/layout.html').toString()

  return (req, res, next) => {
    if (req.method !== 'GET') { return next() }

    const app = renderServerSide(db)
    const content = layout
      .replace(
        '<div id="root"></div>',
        `<div id="root">${app.html}</div>`
      )
      .replace(
        '</head>',
        `<script>window.__INIT_STATE__=${app.state}</script></head>`
      )
    res.writeHead(200, {
      'Content-Type': 'text-html',
      'Content-Length': Buffer.from(content).length
    })
    res.end(content)
  }
}
```

### <a id="server-webpack"></a>webpack.config.js

Finally I make it all work together by updating webpack to import client files as JSX and to omit production imports in development:

```jsx
// webpack.config.js
...
const { DefinePlugin } = require('webpack')

const config = {
  ...
  module: {
    loaders: [
      {
        test: /\.jsx?$/,
        include: path.resolve(__dirname, '..', 'client', 'src'),
        loader: require.resolve('babel-loader'),
        options: {
          babelrc: false,
          presets: [require.resolve('babel-preset-react-app')]
        }
      },
      ...
    ]
  },
  plugins: [
    new DefinePlugin({
      'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV)
    })
  ]
  ...
}
```

## <a id="verifying"></a>Verifying that it all works

I start my client app in `client` folder:
```bash
npm start
```
I start my server in `server` folder:
```bash
npm run watch
```
http://localhost:3000 shows my posts as expected.

I shut it all down, go to client and do
```bash
npm run build
cd ../server
npm run build
npm start
```
http://localhost:3000 again shows my posts as expected.

Finally I build the docker image and run it:
```
docker build -t cra-ssr .
docker run -it --rm -p 3000:3000 cra-ssr
```
And again, http://localhost:3000 shows my posts as expected.

## <a id="caching-problem"></a>Caching problem

If I keep default CRA service worker running as it is, my `index.html` file generated by `react-scripts build` will be precached, and visitors will never get my server-rendered `index.html`.

There aren't any options to exclude `index.html` from precaching in CRA at the time of writing and it wouldn't solve the problem fully, since the offline use would be disabled completely.

In the next part of the series I'm going to make `index.html` be served "network-first" using `workbox-cli`, stay tuned!

