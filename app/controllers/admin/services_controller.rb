class Admin::ServicesController < Admin::BaseController
  before_action :set_service, only: [ :edit, :update, :destroy ]

  def index
    @services = Service.fallback_last.includes(:topics)
  end

  def create
    service = Service.new(service_params)

    if service.save
      redirect_to admin_services_path, notice: "Added #{service.name}."
    else
      redirect_to admin_services_path, alert: service.errors.full_messages.to_sentence
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      redirect_to admin_services_path, notice: "Service updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @service.destroy
      redirect_to admin_services_path, notice: "Service deleted."
    else
      redirect_to admin_services_path, alert: @service.errors.full_messages.to_sentence
    end
  end

  private

  def set_service
    @service = Service.find(params[:id])
  end

  def service_params
    params.expect(service: [ :name, :active ])
  end
end
