class TopicsController < ApplicationController
  before_action :require_owner!
  before_action :set_topic, only: [ :edit, :update, :destroy ]

  def create
    topic = Topic.new(topic_params.merge(service: my_service(topic_params[:service_id])))

    if topic.save
      redirect_to services_path, notice: "Added #{topic.name}."
    else
      redirect_to services_path, alert: topic.errors.full_messages.to_sentence
    end
  end

  def edit
    @services = current_user.services.fallback_last
  end

  def update
    if @topic.update(topic_params)
      redirect_to services_path, notice: "Topic updated."
    else
      @services = current_user.services.fallback_last
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @topic.destroy
      redirect_to services_path, notice: "Topic deleted."
    else
      redirect_to services_path, alert: @topic.errors.full_messages.to_sentence
    end
  end

  private

  def set_topic
    @topic = Topic.joins(:service).where(services: { owner_id: current_user.id }).find(params[:id])
  end

  def my_service(id)
    current_user.services.find_by(id: id)
  end

  def topic_params
    params.expect(topic: [ :name, :active, :service_id ])
  end
end
