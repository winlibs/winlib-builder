#include <uv.h>

#include <stdio.h>

static int timer_called;
static int work_called;
static int after_work_called;
static int stat_called;
static int failed;

static void timer_cb(uv_timer_t *timer)
{
	timer_called++;
	uv_close((uv_handle_t *) timer, NULL);
}

static void work_cb(uv_work_t *request)
{
	(void) request;
	work_called++;
}

static void after_work_cb(uv_work_t *request, int status)
{
	(void) request;
	if (status != 0) {
		failed = 1;
	}
	after_work_called++;
}

static void stat_cb(uv_fs_t *request)
{
	if (request->result != 0) {
		failed = 1;
	}
	stat_called++;
	uv_fs_req_cleanup(request);
}

int main(void)
{
	uv_loop_t loop;
	uv_timer_t timer;
	uv_work_t work;
	uv_fs_t stat_request;
	uv_tcp_t tcp;
	struct sockaddr_in address;
	struct sockaddr_storage bound_address;
	int address_length = sizeof(bound_address);

	if (uv_version() != UV_VERSION_HEX || uv_loop_init(&loop) != 0) {
		return 1;
	}
	if (uv_timer_init(&loop, &timer) != 0 ||
		uv_timer_start(&timer, timer_cb, 1, 0) != 0 ||
		uv_queue_work(&loop, &work, work_cb, after_work_cb) != 0 ||
		uv_fs_stat(&loop, &stat_request, ".", stat_cb) != 0 ||
		uv_tcp_init(&loop, &tcp) != 0 ||
		uv_ip4_addr("127.0.0.1", 0, &address) != 0 ||
		uv_tcp_bind(&tcp, (const struct sockaddr *) &address, 0) != 0 ||
		uv_tcp_getsockname(&tcp, (struct sockaddr *) &bound_address, &address_length) != 0) {
		return 1;
	}
	uv_close((uv_handle_t *) &tcp, NULL);
	if (uv_run(&loop, UV_RUN_DEFAULT) != 0 || uv_loop_close(&loop) != 0 ||
		timer_called != 1 || work_called != 1 || after_work_called != 1 ||
		stat_called != 1 || failed) {
		return 1;
	}
	printf("libuv %s: event loop, timer, thread pool, filesystem and TCP checks passed\n", uv_version_string());
	return 0;
}
