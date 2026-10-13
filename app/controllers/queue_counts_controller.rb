# What the favicon polls. A tab left open in the background can't be told
# about a ticket filed from Slack, so it asks once a minute instead.
class QueueCountsController < ApplicationController
  # The login redirect would remember this as where to go after signing in,
  # and nobody wants to land on a line of JSON.
  skip_before_action :require_login

  def show
    return head :unauthorized unless current_user

    render json: queue_counts || { open: 0, in_progress: 0 }
  end
end
