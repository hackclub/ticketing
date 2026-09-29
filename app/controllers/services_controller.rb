# Everyone who takes tickets keeps their own list of what can be filed under.
class ServicesController < ApplicationController
  before_action :require_owner!
  before_action :set_service, only: [ :edit, :update, :destroy ]

  def index
    @services = current_user.services.fallback_last.includes(:topics)
  end

  def create
    service = current_user.services.new(service_params)

    if service.save
      redirect_to services_path, notice: "Added #{service.name}."
    else
      redirect_to services_path, alert: service.errors.full_messages.to_sentence
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      redirect_to services_path, notice: "Service updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @service.destroy
      redirect_to services_path, notice: "Service deleted."
    else
      redirect_to services_path, alert: @service.errors.full_messages.to_sentence
    end
  end

  private

  # Scoped to your own, so a guessed id can't reach somebody else's.
  def set_service
    @service = current_user.services.find(params[:id])
  end

  def service_params
    params.expect(service: [ :name, :active ])
  end
end
