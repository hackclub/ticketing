# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

SERVICES = {
  "Website" => [ "Bug", "Content Update", "New Page Request" ],
  "Slack" => [ "Access Request", "Bot Issue", "Channel Request" ],
  "Events / YSWS" => [ "Question", "Approval Request" ],
  "Other" => [ "General Request" ]
}.freeze

# Services belong to whoever takes the tickets filed under them, so seeding
# needs somebody to own them.
owner = User.admins.first || User.first
abort "Seed an admin first: no user to own these services." if owner.nil?

SERVICES.each do |service_name, topic_names|
  service = owner.services.find_or_create_by!(name: service_name)

  topic_names.each do |topic_name|
    service.topics.find_or_create_by!(name: topic_name)
  end
end
