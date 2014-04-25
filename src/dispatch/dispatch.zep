namespace Dispatch;

class Dispatch {
	private error_callbacks = [];
	private _config = [];
	private quoted = -1;
	private token = "";
	private store = [];
	private cache = [];
	private source = [];
	private session_active = false;
	private headers = [];
	private content = "";
	private stash = [];
	private symfilters = [];
	private bindings = [];
	private symcache = [];
	private before_regexp_callbacks = [];
	private before_callbacks = [];
	private after_regexp_callbacks = [];
	private after_callbacks = [];
	public routes = [];

	/**
	 * Function for setting http error code handlers and for
	 * triggering them. Execution stops after an error callback
	 * handler finishes.
	 *
	 * @param int $code http status code to use
	 * @param callable optional, callback for the error
	 *
	 * @return void
	 */
	public function error(int code, callback = null) -> void {
		string str_code, message;
		let str_code = code;

		// this is a hook setup, save and return
		if is_callable(callback) {
			let this->error_callbacks[str_code] = callback;
			return;
		}

		// see if passed callback is a message (string)
		let message = is_string(callback) ? callback : "Page Error(｢･ω･)｢";

		// set the response code
		header(
			_SERVER["SERVER_PROTOCOL"] . " " . str_code . " " . message,
			true,
			code
		);

		// bail early if no handler is set
		if !isset this->error_callbacks[str_code] {
			return;
		}

		// if we got callbacks, try to invoke
		var func;
		if fetch func, this->error_callbacks[str_code] {
			call_user_func(func, str_code);			
		}
	}

	/**
	 * Sets or gets an entry from the loaded config.ini file. If the $key passed
	 * is 'source', it expects $value to be a path to an ini file to load. Calls
	 * to config('source', 'inifile.ini') will aggregate the contents of the ini
	 * file into config().
	 *
	 * @param string $key setting to set or get. passing null resets the config
	 * @param string $value optional, If present, sets $key to this $value.
	 *
	 * @return mixed|null value
	 */
	public function config(key = "", value = null) {
		// if key is source, load ini file and return
		if key === "source" {
			if !file_exists(value) {
				trigger_error(
					"File passed to config('source') not found",
					E_USER_ERROR
				);
			}
			let this->_config = array_merge(this->_config, parse_ini_file(value, true));
			return;
		}

		// reset configuration to default
		if (key === ""){
		 	let this->_config = [];
			return;
		}

		// setting multiple settings. merge together if $key is array.
		if is_array(key) {
			var keys;
			let keys = array_filter(array_keys(key), "is_string");
			let keys = array_intersect_key(key, array_flip(keys));
			let this->_config = array_merge(this->_config, keys);
			return;
		}

		// for all other string keys, set or get
		if value === null {
			return isset this->_config[key] ? this->_config[key] : null;
		} else {
			let this->_config[key] = value;
		}
	}

	/**
	 * Utility for setting cross-request messages using cookies,
	 * referred to as flash messages (invented by Rails folks).
	 * Calling flash('key') will return the message and remove
	 * the message making it unavailable in the following request.
	 * Calling flash('key', 'message', true) will store that message
	 * for the current request but not available for the next one.
	 *
	 * @param string $key name of the flash message
	 * @param string $msg string to store as the message
	 * @param bool $now if the message is available immediately
	 *
	 * @return $string message for the key
	 */
	public function flash(string key, msg = null, boolean now = false) -> string {

		if this->token === "" {
			let this->token = this->config("dispatch.flash_cookie");
			let this->token = !this->token ? "_F" : this->token;
		}

		// get messages from cookie, if any, or from new hash
		if empty this->store {
			var jstore;
			let jstore = this->cookie(this->token);
			if !empty jstore {
				let this->store = json_decode(jstore, true);
			}
		}

		// if this is a fetch request
		if msg == null {
			var val;
			if fetch val, this->store[key] {
				let this->cache[key] = val;
				unset(this->store[key]);
				this->cookie(this->token, json_encode(this->store));
			}

			return isset this->cache[key] ? this->cache[key] : "";
		} 

		// cache it and put it in the cookie
		let this->store[key] = msg;
		let this->cache[key] = msg;

		// rewrite cookie unless now-type
		if !now {
			this->cookie(this->token, json_encode(this->store));
		}

		// return the new message
		return msg;
	}


	/**
	 * Convenience wrapper for urlencode()
	 *
	 * @param string $str string to encode.
	 *
	 * @return string url encoded string
	 */
	public function url(string str) -> string {
	  return urlencode(str);
	}

	/**
	 * Wraps around $_COOKIE and setcookie().
	 *
	 * @param string $name name of the cookie to get or set
	 * @param string $value optional. value to set for the cookie
	 * @param integer $expire default 1 year. expiration in seconds.
	 * @param string $path default '/'. path for the cookie.
	 *
	 * @return string value if only the name param is passed.
	 */
	public function cookie(string name, string value = "", int expire = 31536000, string path = "/") {
		if this->quoted < 0 {
			let this->quoted = get_magic_quotes_gpc();
		}

		if func_num_args() === 1 {
			return isset _COOKIE[name] ? (this->quoted ? stripslashes(_COOKIE[name]): _COOKIE[name]) : null;
		}

	  	setcookie(name, value, time() + expire, path);
	}

	/**
	 * Convenience wrapper for htmlentities().
	 *
	 * @param string $str string to encode
	 * @param string $enc encoding to use.
	 * @param string $flags htmlentities() flags
	 *
	 * @return string encoded string
	 */
	public function html(string str, int flags = -1, string enc = "UTF-8", boolean denc = true) -> string {
		let flags = (flags < 0 ? ENT_QUOTES : flags);
		return htmlentities(str, flags, enc, denc);
	}

	/**
	 * Helper for getting values from $_GET, $_POST and route
	 * symbols.
	 *
	 * @param string $name optional. parameter to get the value for
	 * @param mixed $dv optional. default value for param
	 *
	 * @return mixed param value.
	 */
	public function params(name, dv = "") {

		// initialize source if this is the first call
		if empty this->source {
			let this->source = array_merge(_GET, _POST);
			//5.4.0	 Always returns FALSE because the magic quotes feature was removed from PHP.
			if get_magic_quotes_gpc() {
				let this->source = this->stripslashes_recursive(this->source);
			}
		}

		// this is a value fetch call
		if is_string(name) {
			return isset this->source[name] ? this->source[name] : dv;
		}

		// used by on() for merging in route symbols.
		let this->source = array_merge(this->source, name);
	}

	private function stripslashes_recursive(arr) {
		var k, v;
		for k, v in arr {
			if is_array(v) {
				let arr[k] = this->stripslashes_recursive(v);
			} else {
				let arr[k] = stripslashes(v);
			}
		}
		return arr;
	}

	/**
	 * Wraps around $_SESSION
	 *
	 * @param string $name name of session variable to set
	 * @param mixed $value value for the variable. Set this to null to
	 *   unset the variable from the session.
	 *
	 * @return mixed value for the session variable
	 */
	public function session(string name, value = null) {
		// stackoverflow.com: 3788369
		if (this->session_active === false) {
			var current = "";
			let current = ini_get("session.use_trans_sid");
			if current == false {
				trigger_error("Call to session() requires that sessions be enabled in PHP", E_USER_ERROR);
			}

			var test, prev, peek;
			let test = "mix" . current . current;

			let prev = ini_set("session.use_trans_sid", test);
			let peek = ini_set("session.use_trans_sid", current);

			if peek !== current && peek !== false {
				session_start();
				let this->session_active = true;
			}
		}

		if func_num_args() === 1 {
			return isset _SESSION[name] ? _SESSION[name] : null;
		}

		var session = "_SESSION";
		let {session} = array_merge(_SESSION, [name: value]);
	}

	/**
	 * Convenience wrapper for accessing http request headers.
	 *
	 * @param string $key name of http request header to fetch
	 *
	 * @return string value for the header, or null if header isn't there.
	 */
	public function request_headers(key = null) {
		// if first call, pull headers
		if empty this->headers {
			// if we're not on apache
			var k, v;
			for k, v in _SERVER {
				if substr(k, 0, 5) === "HTTP_" {
					let this->headers[strtolower(str_replace("_", "-", substr(k, 5)))] = v;
				}
			}
		}

		// header fetch
		if key !== null {
			let key = strtolower(key);
			return isset this->headers[key] ? this->headers[key] : null;
		}

		return this->headers;
	}

	/**
	 * Convenience function for reading in the request body. JSON
	 * and form-urlencoded content are automatically parsed and returned
	 * as arrays.
	 *
	 * @param boolean $load if false, you get a temp file path with the data
	 *
	 * @return mixed raw string or decoded JSON object
	 */
	public function request_body(boolean load = true) {
		// called before, just return the value
		if !empty this->content {
			return this->content;
		}

		// get correct content-type of body (hopefully)
		var content_type, content;
		let content_type = isset _SERVER["HTTP_CONTENT_TYPE"] ? _SERVER["HTTP_CONTENT_TYPE"] : _SERVER["CONTENT_TYPE"];

		// try to load everything
		if load {
			let content = file_get_contents("php://input");
			let content_type = preg_split("/ ?; ?/", content_type);
	
			// if json, cache the decoded value
			if content_type[0] == "application/json" {
				let content = json_decode(content, true);
			} 
			if content_type[0] == "application/x-www-form-urlencoded" {
				parse_str(content, content);
			}
			return content;

		}

		// create a temp file with the data
		var path, temp, data;
		let path = tempnam(sys_get_temp_dir(), "disp-");
		let temp = fopen(path, "w");
		let data = fopen("php://input", "r");

		// 8k per read
		var buff;
		loop {
			let buff = fread(data, 8192);
			if !buff { break; }
			fwrite(temp, buff);			
		}

		fclose(temp);
		fclose(data);

		return path;
	}

	/**
	 * Creates a file download response for the specified path using the passed
	 * filename. If $sec_expires is specified, this duration will be used
	 * to specify the download's cache expiration header.
	 *
	 * @param string $path full path to the file to stream
	 * @param string $filename filename to use in the content-disposition header
	 * @param int $sec_expires optional, defaults to 0. in seconds.
	 *
	 * @return void
	 */
	public function send(string path, string filename, int sec_expires = 0) -> void {
		var mime, etag, lmod, size;
		let mime = "application/octet-stream";
		let etag = md5(path);
		let lmod = filemtime(path);
		let size = filesize(path);
		 
		// cache headers
		header("Pragma: public");
		header("Last-Modified: " . gmdate("D, d M Y H:i:s", lmod) . " GMT");
		header("Cache-Control: maxage=" . sec_expires);

	  	// if we want this to persist
	  	if sec_expires > 0 {
			header("ETag: " . etag);
			header("Expires: " . gmdate("D, d M Y H:i:s", time()+sec_expires) . " GMT");
	  	}

	  	// file info
		header("Content-Disposition: attachment; filename=" . urlencode(filename));
		header("Content-Type: " . mime);
		header("Content-Length: " . size);

		// no time limit, clear buffers
		set_time_limit(0);
		ob_clean();

		// dump the file
		var fp;
		let fp = fopen(path, "rb");
		while !feof(fp) {
			echo fread(fp, 1024*8);
			ob_flush();
			flush();
		}
		fclose(fp);
	}

	/**
	 * File upload wrapper. Returns a hash containing file
	 * upload info. Skips invalid uploads based on
	 * is_uploaded_file() check.
	 *
	 * @param string $name input file field name to check.
	 *
	 * @param array info of file if found.
	 */
	public function files(string name) {
		if !isset _FILES[name] {
			return null;
		}

		var result = null;


		// if file field is an array
		if is_array(_FILES[name]["name"]) {
			let result = [];

			// consolidate file info
			var v1, v2, k1, k2;
			for k1, v1 in _FILES[name] {
				for k2, v2 in v1 {
					let result[k2][k1] = v2;
				}
			}

			// remove invalid uploads
			for k1, v1 in result {
				if !is_uploaded_file(v1["tmp_name"]) {
					unset(result[k1]);
				}
			}
	    	// if no entries, null, else, return it
			let result = !count(result) ? null : array_values(result);
		} else {
			// only if file path is valid
			if is_uploaded_file(_FILES[name]["tmp_name"]) {
				let result = _FILES[name];
			}
		}
	 	
	 	// null if no file or invalid, hash if valid
		return result;
	}

	/**
	 * A utility for passing values between scopes. If $value
	 * is passed, $name will be set to $value. If $value is not
	 * passed, the value currently mapped against $name will be
	 * returned instead.
	 *
	 * @param string $name name of variable to store.
	 * @param mixed $value optional, value to store against $name
	 *
	 * @return mixed value mapped to $name
	 */
	public function scope(string name, value = null) {
		if value === null {
			return isset this->stash[name] ? this->stash[name] : null;
		}
		let this->stash[name] = value;
		return value;
	}

	/**
	 * Returns the client's IP address.
	 *
	 * @return string client's ip address.
	 */
	public function ip() -> string {
		if isset _SERVER["HTTP_CLIENT_IP"] {
			return _SERVER["HTTP_CLIENT_IP"];
		}

		if isset _SERVER["HTTP_X_FORWARDED_FOR"] {
			return _SERVER["HTTP_X_FORWARDED_FOR"];
		}

		return _SERVER["REMOTE_ADDR"];
	}

	/**
	 * Performs an HTTP redirect.
	 *
	 * @param int|string http code for redirect, or path to redirect to
	 * @param string|bool path to redirect to, or condition for the redirect
	 * @param bool condition for the redirect, true means it happens
	 *
	 * @return void
	 */
	public function redirect(string path, int code = 302, boolean condition = true) -> void {
		if !condition {
			return;
		}
		header("Location: " . path, true, code);
	}

	/**
	 * Convenience function for storing/fetching content to be
	 * plugged into the layout within render().
	 *
	 * @param string $value optional, value to use as content.
	 *
	 * @return string content
	 */
	public function content(value = null) {
		return this->scope("$content$", value);
	}

	/**
	 * Returns the contents of the template $view, using
	 * $locals (optional).
	 *
	 * @param string $view path to partial
	 * @param array $locals optional, hash to load as scope variables
	 *
	 * @return string content of the partial.
	 */
	public function template(view, locals = []) -> string {
		var view_root;
		let view_root = this->config("dispatch.views");
		if !view_root {
			trigger_error("config('dispatch.views') is not set.", E_USER_ERROR);
		}

		extract(locals, EXTR_SKIP);

		var view_file, html = "";
		let view_file = view_root . DIRECTORY_SEPARATOR . view . ".html.php";

		if file_exists(view_file) {
			ob_start();
			require view_file;
			let html = ob_get_clean();
		} else {
			trigger_error("Template [{$view}] not found.", E_USER_ERROR);
		}

	  	return html;
	}

	/**
	 * Returns the contents of the partial $view, using $locals (optional).
	 * Partials differ from templates in that their filenames start with _.
	 *
	 * @param string $view path to partial
	 * @param array $locals optional, hash to load as scope variables
	 *
	 * @return string content of the partial.
	 */
	public function partial(view, locals = []) -> string {
		var path;
		let path = basename(view);
		let view = preg_replace("/" . path ."$/", "_" . path, view);
		return this->template(view, locals);
	}

	/**
	 * Renders the contents of $view using $locals (optional), into
	 * $layout (optional). If $layout === false, no layout will be used.
	 *
	 * @param string $view path to the view file to render
	 * @param array $locals optional, hash to load into $view's scope
	 * @param string|bool path to the layout file to use, false means no layout
	 *
	 * @return string contents of the view + layout
	 */
	public function render(view, locals = [], layout = null) {

		// load the template and plug it into content()
		var content;
		let content = this->template(view, locals);
		this->content(trim(content));

	  	// if we're to use a layout
	  	if layout !== false {

	  		// layout = null means use the default
	  		if layout === null {
	  			let layout = this->config("dispatch.layout");
	  			let layout = layout == null ? "layout" : layout;
	  		}
	    	
	    	// load the layout template, with content() already populated
			echo this->template(layout, locals);
			return;
	  	}

		// no layout was to be used (layout = false)
		echo content;
	}

	/** 
	 * Convenience wrapper for creating route handlers
	 * that show nothing but a view.
	 *
	 * @param string $file name of the view to render
	 * @param array|callable $locals locals array or callable that return locals
	 * @param string|boolean $layout layout file to use
	 *
	 * @return callable handler function
	 */
	public function disp_inline(file, locals = null, layout = "layout") {
		//not support now!!
	}

	/**
	* Spit headers that force cache volatility.
	*
	* @param string $content_type optional, defaults to text/html.
	*
	* @return void
	*/
	public function nocache() {
		header("Expires: Tue, 13 Mar 1979 18:00:00 GMT");
		header("Last-Modified: " . gmdate("D, d M Y H:i:s") . " GMT");
		header("Cache-Control: no-store, no-cache, must-revalidate");
		header("Cache-Control: post-check=0, pre-check=0", false);
		header("Pragma: no-cache");
	}

	/**
	* Dump a JSON response along with the appropriate headers.
	*
	* @param mixed $obj object to serialize into JSON
	* @param string $func for JSONP output, this is the callback name
	*
	* @return void
	*/
	public function json(obj, func = null) {
		this->nocache();
		if !func {
			header("Content-type: application/json");
			echo json_encode(obj);
		} else {
			header("Content-type: application/javascript");
			echo ";{" .func . "(" . json_encode(obj) .");";
		}
	}

	/**
	* Creates callbacks (filters) against certain
	* symbols within a route. Whenever $sym is encountered
	* in a route, the filter is invoked.
	*
	* @param string $sym symbol to create a filter for
	* @param callable|mixed filter or value to pass to the filter
	*
	* @return void
	*/
	public function filter(symbol, callback = null) {
		// this is a mapping call
		if is_callable(callback) {
			let this->symfilters[symbol][] = callback;
			return;
		}

		// run symbol filters
		var sym, val;
		for sym, val in symbol {
			if isset this->symfilters[sym] {
				for callback in this->symfilters[sym] {
					call_user_func(callback, val);
				}
			}
		}
	}

	/**
	* Filters parameters for certain symbols that are passed to the request
	* callback. Only one callback can be bound to a symbol. The original request
	* parameter can be accessed using the param() function.
	*
	* @param string $symbol symbol to bind a callback to
	* @param callable|mixed callback to bind to that symbol
	*
	* @return mixed transformed value based on the param
	*/
	public function bind(symbol, callback = null) {

		// Bind a callback to the symbol
		if is_callable(callback) {
			let this->bindings[symbol] = callback;
			return;
		}

		// If the symbol is given but is not an array - see if we have filtered it
		if !is_array(symbol) {
			return isset this->symcache[symbol] ? this->symcache[symbol] : null;
		}

		// If callbacks are bound to symbols, apply them
		var values = [];
		var sym, val, rt;
		for sym, val in symbol {
			let rt = null;
			if isset this->bindings[sym] {
				let rt = call_user_func(this->bindings[sym], val);
				let this->symcache[sym] = rt;
			}
			let val = rt ? rt : val;
			let values[sym] = val;
		}

		return values;
	}

	/**
	 * Function for mapping callbacks to be invoked before each request.
	 * If called with two args, with first being regex, callback is only
	 * invoked if the regex matches the request URI.
	 *
	 * @param callable|string $callback_or_regex callable or regex
	 * @param callable $callback required if arg 1 is regex
	 *
	 * @return void
	 */
	public function before(func = null, rexp = null) {
		var args;
		let args = func_get_args();
		let func = array_pop(args);
		let rexp = array_pop(args);

		// mapping call
		if is_callable(func) {
			if rexp {
				let this->before_regexp_callbacks[rexp] = func;
			} else {
				let this->before_callbacks[] = func;
			}

			return;
		}

		// remap args for clarity
		var verb, path;
		let verb = rexp;
		let path = substr(func, 1);

		// let's run regexp callbacks first
		for rexp, func in this->before_regexp_callbacks {
			if preg_match(rexp, path) {
				call_user_func_array(func, [verb, path]);
			}
		}

		// call generic callbacks
		for func in this->before_callbacks {
			call_user_func_array(func, [verb, path]);
		}
	}

	/**
	 * Function for mapping callbacks to be invoked after each request.
	 * If called with two args, with first being regex, callback is only
	 * invoked if the regex matches the request URI.
	 *
	 * @param callable|string $callback_or_regex callable or regex
	 * @param callable $callback required if arg 1 is regex
	 *
	 * @return void
	 */
	public function after(func = null, rexp = null) {
		var args;
		let args = func_get_args();
		let func = array_pop(args);
		let rexp = array_pop(args);

		// mapping call
		if is_callable(func) {
			if rexp {
				let this->after_regexp_callbacks[rexp] = func;
			} else {
				let this->after_callbacks[] = func;
			}

			return;
		}

		// remap args for clarity
		var verb, path;
		let verb = rexp;
		let path = func;

		// let's run regexp callbacks first
		for rexp, func in this->after_regexp_callbacks {
			if preg_match(rexp, path) {
				call_user_func_array(func, [verb, path]);
			}
		}

		// call generic callbacks
		for func in this->after_callbacks {
			call_user_func_array(func, [verb, path]);
		}
	}

	/**
	 * Maps a callback or invokes a callback for requests
	 * on $pattern. If $callback is not set, $pattern
	 * is matched against all routes for $method, and the
	 * the mapped callback for the match is invoked. If $callback
	 * is set, that callback is mapped against $pattern for $method
	 * requests.
	 *
	 * @param string $method HTTP request method or method + path
	 * @param string $pattern path or callback
	 * @param callable $callback optional, handler to map
	 *
	 * @return void
	 */
	public function on(method, string path, callback = null) {
		var regexp = null;
		let path = trim(path, "/");

		// a callback was passed, so we create a route definition
		if is_callable(callback) {

			let regexp = preg_replace("@:(\\w+)@", "(?P<``\\1>\\w+)", path); //something wrong <\\1> emtpy!
			let regexp = preg_replace("@``@", "", regexp);
			if is_array(method) {
				let method = array_map("strtoupper", method);
				var m;
				for m in method {
					let this->routes[m]["@^" . regexp . "$@"] = callback;
				}
			}

			if is_string(method) {
				let method = strtoupper(method);
				let this->routes[method]["@^" . regexp . "$@"] = callback;
			}

			return;
		}

		// setup method and rexp for dispatch
		let method = strtoupper(method);

		// lookup a matching route
		var values, _tmp;
		if isset this->routes[method] {
			let _tmp = this->get_finder(this->routes[method], path);
			let regexp = _tmp[0];
			let callback = _tmp[1];
			let values = _tmp[2];

		}

		// if no match, try the any-method handlers
		if !regexp && isset this->routes["*"] {
			let _tmp = this->get_finder(this->routes["*"], path);
			let regexp = _tmp[0];
			let callback = _tmp[1];
			let values = _tmp[2];
		}

		// we got a match
		if regexp {
			// construct the params for the callback
			var tokens;
			let tokens = array_filter(array_keys(values), "is_string");
			let values = array_map("urldecode", array_intersect_key(values, array_flip(tokens)));

	    	// setup + dispatch
	    	var buff;
	    	ob_start();
	    	this->params(values);
	    	this->filter(values);
	    	this->before(method, "@" . path);
	    	call_user_func_array(callback, array_values(this->bind(values)));
	    	this->after(method, path);
	    	let buff = ob_get_clean();

	    	if method !== "HEAD" {
	    		echo buff;
	    	}
		} else {
			this->error(404, "Page not found!");
		}
	}

	private function get_finder(routes, path) {
		var values = null;
		var regexp, callback;
		for regexp, callback in routes {
			if preg_match(regexp, path, values) {
				return [regexp, callback, values];
			}
		}
		return [null, null, null];
	}

	/**
	 * Entry point for the library.
	 *
	 * @param string $method optional, for testing in the cli
	 * @param string $path optional, for testing in the cli
	 *
	 * @return void
	 */
	public function dispatch() {

		// see if we were invoked with params
		var method;
		let method = strtoupper(_SERVER["REQUEST_METHOD"]);
		if method == "POST" {
			if isset _SERVER["HTTP_X_HTTP_METHOD_OVERRIDE"] {
				let method = _SERVER["HTTP_X_HTTP_METHOD_OVERRIDE"];
			} else {
				let method = this->params("_method") ? this->params("_method") : method;
			}
		}
		
		// get the request_uri basename
		var path;
		let path = parse_url(_SERVER["REQUEST_URI"], PHP_URL_PATH);
		
		// remove dir path if we live in a subdir
		var base;
		let base = this->config("dispatch.url");
		if base {
			let base = parse_url(base, PHP_URL_PATH);
			var _tmp_str;
			let _tmp_str = "@^" . preg_quote(base) . "@";
			let path = preg_replace("@^" . preg_quote(base) . "@", "", path);
		}

		// remove router file from URI
		var stub;
		let stub = this->config("dispatch.router");
		if stub {
			let path = preg_replace("@^/?" . preg_quote(trim(stub, ".")) . "@i", "", path);
		}

		let path = trim(path, "/");

		// dispatch it
		this->on(method, path);
	}
}
