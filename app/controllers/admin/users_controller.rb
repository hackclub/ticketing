class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [ :show, :update ]

  def index
    # One query with the counts in it, rather than one per person.
    @users = User.left_joins(:tickets).group(:id).order(:name)
                 .select("users.*, COUNT(tickets.id) AS filed_count")
  end

  def show
    @tickets = @user.tickets.order(created_at: :desc).includes(:service, :topic)
  end

  # Two independent switches, each posted on its own, so whichever arrives is
  # the one that changes.
  def update
    @user.update!(priority_boost: user_params[:priority_boost]) if user_params.key?(:priority_boost)
    set_receiving(user_params[:receives_tickets]) if user_params.key?(:receives_tickets)

    if user_params.key?(:admin) && (refusal = set_admin(user_params[:admin]))
      return redirect_to admin_user_path(@user), alert: refusal
    end

    redirect_to admin_user_path(@user), notice: "#{@user.display_name} updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_user_path(@user), alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def set_receiving(value)
    if ActiveModel::Type::Boolean.new.cast(value)
      @user.start_receiving_tickets!
    else
      @user.stop_receiving_tickets!
    end
  end

  # Returns a reason when the change is refused, nil when it's done.
  def set_admin(value)
    wanted = ActiveModel::Type::Boolean.new.cast(value)
    return if wanted == @user.admin?

    if @user == current_user
      "You can't change your own admin access — ask another admin."
    elsif !wanted && @user.configured_admin?
      "#{@user.display_name} is an admin through ADMIN_EMAILS or ADMIN_SLACK_IDS, " \
        "so it would come back at their next sign-in. Take them off that list instead."
    else
      wanted ? @user.make_admin! : @user.revoke_admin!
      nil
    end
  end

  def user_params
    params.expect(user: [ :priority_boost, :receives_tickets, :admin ])
  end
end
