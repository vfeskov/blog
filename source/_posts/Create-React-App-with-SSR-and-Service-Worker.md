---
title: 'Create React App with SSR and Service Worker'
date: 2017-12-29 01:29:44
tags:
  - CRA
  - SSR
  - Node.js
  - JS
  - Service Worker
  - CRA with SSR series
---

CRA service worker caches `index.html` and serves the cache instead of requesting it from the server. It breaks server side rendering and in this post I'm going to fix it.

<!-- more -->

This post is the third one in the [series](https://vfeskov.com/tags/CRA-with-SSR-series/) dedicated to React Server Side Rendering.

- [Source code for the post](https://github.com/vfeskov/cra-ssr/tree/part-3-service-worker)
- [Commit that fixes service worker](https://github.com/vfeskov/cra-ssr/commit/d269f55e9f9c83cb6a67033499c51f5a778bdb4a)
- [Live project this series is based on](https://github.com/vfeskov/win-a-beer)

## Index

- [Problem in depth](#problem)
- [Why not just disable](#why)
- [How to fix](#how)
- [Client](#client)
  - [client/package.json](#client-package)
  - [client/workbox-cli-config.js](#client-workbox-config)
  - [client/src/service-worker.js](#client-src-service-worker)
- [Verifying that it works](#verifying)
- [What about routing?](#routing)

## Problem in depth <a id="problem" href="#problem">#</a>

CRA adds `build` script to `package.json`, which in turn calls `react-scripts build`:

```json
{
  ...
  "scripts": {
    "build": "react-scripts build",
    ...
  }
}
```

Now, that command puts a production version of the app in `build/` folder and then adds `service-worker.js` file to it. That file contains instructions to cache everything inside the `build/` folder, including `index.html`. When a user returns to the website, service worker will always serve cache until the next deployment.

With server side rendering `index.html` is supposed to be dynamic, e.g., it should have recent blog posts pre-rendered when they are added to the database, and CRA service worker simply doesn't support it: once a visitor saw 5 posts, he will never see the 6th until next deployment, and deploying every time you change something in the db is not an option.

## Why not just disable <a id="why" href="#why">#</a>

Why not just disable the service worker then? Well, because service worker lets users visit your websites offline even months after they last visited it.

There are awesome tools like [Pocket](https://getpocket.com/) that let you download a website so you could browse it offline later. If your website has a service worker, these tools are not needed: users just naturally browse the website offline in their browsers.

## How to fix <a id="how" href="#how">#</a>

Back to the problem, how am I going to fix it?

I'm going to override the `service-worker.js` file that `react-scripts build` generates with my own that I'm going to make with [Workbox](https://developers.google.com/web/tools/workbox/).

My service worker will cache all the static files the original one would, but `index.html` it will serve network-first: if there's internet, it will fetch the file from the server, otherwise it will serve cache.

## Client <a id="client" href="#client">#<a/>

My [project](https://github.com/vfeskov/cra-ssr/tree/part-2-enabling-ssr) consists of `client/` and `server/` folders, `client/` holds app scaffolded with create-react-app.

`npm run build` in `client/` not only builds production version in `build/` but also moves this folder to the `server/`:
```json
{
  ...
  "scripts": {
    "build": "react-scripts build && npm run move-build-to-server",
    "move-build-to-server": "mv build _build && mv _build ../server && cd ../server && rm -rf public && mv _build public && mv public/index.html public/layout.html",
    ...
  }
}
```

### client/package.json <a id="client-package" href="#client-package">#</a>

I'm going to install `workbox-cli` and `workbox-sw` to generate replacement service worker:

```bash
npm install --save workbox-cli@2.1.2 && workbox-sw@2.1.2
```

Next, I'm going to squeeze my SW replacement script in between `react-scripts build` and `npm run move-build-to-server` in the build script:

```json
{
  ...
  "scripts": {
    "build": "react-scripts build && npm run generate-sw && npm run move-build-to-server",
    "generate-sw": "workbox inject:manifest && cp node_modules/workbox-sw/build/importScripts/workbox-sw.prod* build",
    ...
  }
}
```
`generate-sw` script will use configuration from `workbox-cli-config.js` and it will do the following:

1. Locate `src/service-worker.js` template file
2. Inject cached filenames from `build/` folder into the template
3. Override existing `build/service-worker.js` with the result
4. Copy `workbox-sw` library file to `build/` to be imported inside the service worker

### client/workbox-cli-config.js <a id="client-workbox-config" href="#client-workbox-config">#</a>

I'm going to create configuration for the `generate-sw` script:
```js
module.exports = {
  "globDirectory": "build/",
  "globPatterns": [
    "**/*.{json,ico,html,js,css,woff2,woff}"
  ],
  "swSrc": "./src/service-worker.js",
  "swDest": "build/service-worker.js",
  "globIgnores": [
    "../workbox-cli-config.js",
    "asset-manifest.json",
    "index.html"
  ]
};
```
It will make the result service worker pre-cache all files in `build/` folder except `asset-manifest.json` and `index.html`. Only difference from default CRA service worker is `index.html`.

The config also states to use `./src/service-worker.js` as the template.

### client/src/service-worker.js <a id="client-src-service-worker" href="#client-src-service-worker">#</a>

In my [other project](https://github.com/vfeskov/win-a-beer) I have authentication enabled and the website renders differently depending on visitor being logged in or not.

Invalidating cache there was a hard problem, e.g., if a user logs out, goes offline and comes back to the website, they shouldn't see cache as if they're still logged in.

Following service worker solved all the issues I encountered and it's generic enough to be used as a base for any project:


```js
importScripts('workbox-sw.prod.v2.1.2.js')

const workbox = new WorkboxSW({
  skipWaiting: true,
  clientsClaim: true
})

// following array will be filled with filenames
// from `build/` folder when `generate-sw` script runs
workbox.precache([])

// cache index.html when service worker gets installed
self.addEventListener('install', updateIndexCache)

// the listener catches all http requests coming from
// the browser at my website
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url)
  // I want to let event through without modifying if
  // any of the following conditions are met
  if (
    // if it's a request for a precached file
    isPrecached(url) ||
    // if it's a request for a static file (not index.html)
    isStaticFile(url) ||
    // if it's an external request to another domain
    isExternal(url) ||
    // if it's a GET request to /api/* url
    isGetApi(event, url)
  ) { return }

  // when an API action happens, for example,
  // "DELETE /api/session" that logs user out,
  // I let the request through and update index.html
  // cache after it's done
  if (event.request.method !== 'GET') {
    return event.respondWith(
      fetch(event.request)
        .then(response => {
          updateIndexCache()
          return response
        })
    )
  }

  // I serve index.html network-first on any request that
  // reaches this line
  event.respondWith(
    fetch(indexRequest())
      .then(response => {
        updateIndexCache()
        return response
      })
      .catch(() => caches.match(indexRequest()))
  )
})

function isPrecached({ href }) {
  return workbox._revisionedCacheManager._parsedCacheUrls.includes(href)
}

function isStaticFile({ pathname }) {
  return pathname.includes('.') && pathname !== '/index.html'
}

function isExternal({ origin }) {
  return origin !== location.origin
}

// if your api has a different prefix, e.g., /api/v1/,
// just update RegExp accordingly
function isGetApi({ request }, { pathname }) {
  return request.method === 'GET' && /^\/api\/.+/.test(pathname)
}

async function updateIndexCache() {
  const cache = await caches.open('dynamic-v1')
  cache.add(indexRequest())
}

function indexRequest() {
  return new Request('index.html', { credentials: 'same-origin' })
}
```

## Verifying that it works <a id="verifying" href="#verifying">#</a>

I [modified](https://github.com/vfeskov/cra-ssr/commit/12779367750312ea8b36410c0882f3d548dfdcd7) the server to simulate real database stored in `server/db.json`.

I go to `client/` folder and do:
```bash
npm run build
cd ../server
npm run build
npm start
```
I open http://localhost:3000 and see my two posts as expected.

Next I add a new post to `server/db.json` file:
```json
[
  ...,
  {
    "id": 3,
    "title": "Cat videos on blockchain?",
    "excerpt": "Hell yeah!"
  }
]
```

I refresh http://localhost:3000 and see the new post as expected.

Next I open DevTools Network tab, tick Offline checkbox and refresh http://localhost:3000. I see the three posts as expected.

## What about routing? <a id="routing" href="#routing">#</a>

If I had a router on client and made server pre-render client routes too, my service worker would only work for the index route.

In the next post I'm going to add routing and adapt service worker accordingly, stay tuned!
