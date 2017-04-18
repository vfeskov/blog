---
title: Override/mock datetime in browser
date: 2017-04-18 20:29:51
intro: A short code snippet that lets override time in protractor or javascript unit-tests.
tags: JavaScript, browser, Date, mock, stub, override
---

For unit tests put it before the specs:

``` js
function overrideDate(theDate) {
  const ActualDate = self.Date;
  self.Date = function() {
    return arguments.length ?
      new ActualDate(...arguments) :
      new ActualDate(theDate);
  };
  const {Date} = self;
  ['prototype', 'UTC', 'parse'].forEach(prop => Date[prop] = ActualDate[prop]);
  Date[Symbol.hasInstance] = date => date instanceof ActualDate;
  Date.now = () => new Date().getTime();
  self.ActualDate = ActualDate;
}

overrideDate('2017-04-18 20:40:12');
```

For protractor tests execute it right after going to the URL:

``` js
function overrideDate(theDate) {
  return browser.executeScript(`
    var ActualDate = Date;
    Date = function() {
      return arguments.length ?
        new ActualDate(...arguments) :
        new ActualDate('${theDate}');
    };
    ['prototype', 'UTC', 'parse'].forEach(prop => Date[prop] = ActualDate[prop]);
    Date[Symbol.hasInstance] = date => date instanceof ActualDate;
    Date.now = () => new Date().getTime();
  `);
}
beforeEach(() => {
  browser.get('/')
    .then(() => overrideDate('2017-04-18 20:40:12'));
});
```

The protractor one works only with strings.
