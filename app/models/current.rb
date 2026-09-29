class Current < ActiveSupport::CurrentAttributes
  # Who is doing this, so the timeline can say so without every call site
  # having to pass an author along.
  attribute :user

  attribute :sql_count, :sql_runtime, :started_at

  def record_query(runtime)
    self.sql_count = sql_count.to_i + 1
    self.sql_runtime = sql_runtime.to_f + runtime
  end

  def elapsed_ms
    return 0.0 if started_at.blank?

    (Time.current - started_at) * 1000
  end
end
