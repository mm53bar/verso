require "test_helper"

# The pool has to be bigger than the thread count, and the reasoning is written
# out in config/database.yml. This test is here because that reasoning is a
# comment, and a comment cannot fail: the stock `max_connections:
# RAILS_MAX_THREADS` line deadlocked production on 2026-08-17 and no test
# noticed, because a deadlock needs concurrency and this suite is single
# threaded. So assert the arithmetic instead of trying to reproduce the hang.
class ConnectionPoolTest < ActiveSupport::TestCase
  test "the pool leaves room for a streaming body thread on every request" do
    # Active Storage's proxy controller includes ActionController::Live, so an
    # in-flight thumbnail holds one connection for the request thread and one
    # for the body thread. Every Puma thread can be doing that at once.
    assert_operator ActiveRecord::Base.connection_pool.size, :>=, puma_threads * 2,
      "a proxied thumbnail needs two connections, so #{puma_threads} Puma " \
      "threads can need #{puma_threads * 2}; a smaller pool deadlocks"
  end

  test "the pool leaves room for Solid Queue, which runs inside Puma" do
    # config/puma.rb starts Solid Queue in the web process, so its supervisor,
    # dispatcher, scheduler and worker threads compete for the same pool.
    assert_operator ActiveRecord::Base.connection_pool.size, :>, puma_threads * 2,
      "Solid Queue runs in this process and needs connections of its own"
  end

  private
    def puma_threads
      Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
    end
end
