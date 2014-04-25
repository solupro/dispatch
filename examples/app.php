<?php
$disp = new \Dispatch\Dispatch();

// settings
$disp->config('dispatch.flash_cookie', '_F');
$disp->config('dispatch.views', __DIR__.'/views');
$disp->config('dispatch.layout', 'layout');
$disp->config('dispatch.url', '');

// before routine
$disp->before(function ($method, $path) {
  echo "BEFORE METHOD: {$method}, BEFORE PATH: {$path}".PHP_EOL;
});

// regex before routine
$disp->before('/^admin\//', function ($method, $path) {
  echo "BEFORE via ADMIN";
});

// after routine
$disp->after(function ($method, $path) {
  echo "AFTER METHOD: {$method}, AFTER PATH: {$path}".PHP_EOL;
});

// regex after routine
$disp->after('/^admin\//', function ($method, $path) {
  echo "AFTER via ADMIN";
});

// routines for testing
$disp->error(404, function () {
  echo "file not found";
});

$disp->on('GET', '/error', function () use ($disp) {
  $disp->error(500);
  });

$disp->on('*', '/any', function () {
  echo "any method route test";
});

$disp->on('GET', '/index', function () use ($disp) {
  $name1 = $disp->params('name');
  $name2 = $_GET['name'];
  echo "GET received {$name1} and {$name2}";
});

$disp->on('POST', '/index', function () use ($disp) {
  $name1 = $disp->params('name');
  $name2 = $_POST['name'];
  echo "POST received {$name1} and {$name2}";
});

$disp->on('PUT', '/index', function () use ($disp) {
  $vars = $disp->request_body();
  echo "PUT received {$vars['name']}";
});

$disp->on('PUT', '/override', function () {
  echo "PUT received via _method";
});

$disp->on('DELETE', '/index/:id', function ($id) {
  echo "DELETE route test";
});

$disp->on('GET', '/json', function () use ($disp) {
  $disp->json(array(
    'name' => 'noodlehaus',
    'project' => 'dispatch'
  ));
});

$disp->on('GET', '/jsonp', function () use ($disp) {
  $disp->json(array(
    'name' => 'noodlehaus',
    'project' => 'dispatch'
  ), 'callback');
});

$disp->on('GET', '/redirect/:code', function ($code) use ($disp) {
  $disp->redirect('/index', (int) $code);
});

$disp->filter('id', function () {
  echo "id found";
});

$disp->on('GET', '/index/:id', function ($id) {
  echo "id = {$id}";
});

$disp->on('GET', '/cookie-set', function () use ($disp) {
  $disp->cookie('cookie', '123');
  echo "cookie set";
});

$disp->on('POST', '/request-headers', function () use ($disp) {
  echo $disp->request_headers('content-type');
});

$disp->on('POST', '/request-body', function () use ($disp) {
  $body = $disp->request_body();
  echo "name={$body['name']}";
});

$disp->on('POST', '/request-body-file', function () use ($disp) {
  $path = $disp->request_body($load = false);
  $body = json_decode(file_get_contents($path), true);
  echo "name={$body['name']}";
});

$disp->on('GET', '/cookie-get', function () use ($disp) {
  $value = $disp->cookie('cookie');
  echo "cookie={$value}";
});

$disp->on('GET', '/params', function () use ($disp) {
  $one = $disp->params('one');
  $two = $disp->params('two');
  echo "one={$one}".PHP_EOL;
  echo "two={$two}".PHP_EOL;
});

$disp->on('GET', '/flash-set', function () use ($disp) {
  $disp->flash('message', 'success');
  $disp->flash('now', time(), true);
});

$disp->on('GET', '/flash-get', function () use ($disp) {
  echo 'message='.$disp->flash('message');
  if (!$disp->flash('now'))
    echo 'flash-now is null';
  else
    echo 'flash-now exists';
});

$disp->on('GET', '/partial/:name', function ($name) use ($disp) {
  echo $disp->partial('partial', array('name' => $name));
});

$disp->on('GET', '/template/:name', function ($name) use ($disp) {
  $disp->render('template', array('name' => $name));
});

/*
$disp->on('GET', '/inline', inline('inline'));
$disp->on('GET', '/inline/locals', inline(
  'inline-locals',
  array('name' => 'dispatch')
));
$disp->on('GET', '/inline/callback', inline('inline-locals', function () {
  return array('name' => 'dispatch');
}));
*/

$disp->on('GET', '/session/setup', function () use ($disp) {
  $disp->session('name', 'i am dispatch');
  $disp->session('type', 'php framework');
});

$disp->on('GET', '/session/check', function () use ($disp) {
  $disp->session('type', null);
  if ($disp->session('type'))
    echo "type is still set";
  echo $disp->session('name');
});

$disp->on('POST', '/upload', function () use ($disp) {
  $info = $disp->files('attachment');
  if (is_array($info) && is_uploaded_file($info['tmp_name']))
    echo "received {$info['name']}";
  else
    echo "failed upload";
});

$disp->on('GET', '/download', function () use ($disp) {
  $disp->send('./README.md', 'readme.txt', 60*60*24*365);
});

$disp->bind('hashable', function ($hashable) {
  return md5($hashable);
});

$disp->on('GET', '/md5/:hashable', function ($hash) use ($disp) {
  echo $hash . '-' . $disp->params('hashable');
});

$disp->bind('author', function ($name) {
  return strtoupper($name);
});

$disp->bind('title', function ($title) use ($disp) {
  return sprintf('%s by %s', strtoupper($title), $disp->bind('author'));
});

$disp->on('GET', '/authors/:author/books/:title', function ($author, $title) {
  echo $title;
});

$disp->on('GET', '/list', function () {
  echo "different list";
});

$disp->on('GET', '/admin/:stub', function ($stub) {
  echo "{$stub}\n";
});

$disp->dispatch();
?>
