class Admin::TopicsController < Admin::BaseController
  before_action :set_topic, only: [ :edit, :update, :destroy ]

  def create
    topic = Topic.new(topic_params)

    if topic.save
      redirect_to admin_services_path, notice: "Added #{topic.name}."
    else
      redirect_to admin_services_path, alert: topic.errors.full_messages.to_sentence
    end
  end

  def edit
    @services = Service.fallback_last
  end

  def update
    if @topic.update(topic_params)
      redirect_to admin_services_path, notice: "Topic updated."
    else
      @services = Service.fallback_last
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @topic.destroy
      redirect_to admin_services_path, notice: "Topic deleted."
    else
      redirect_to admin_services_path, alert: @topic.errors.full_messages.to_sentence
    end
  end

  private

  def set_topic
    @topic = Topic.find(params[:id])
  end

  def topic_params
    params.expect(topic: [ :name, :active, :service_id ])
  end
end
