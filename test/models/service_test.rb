require "test_helper"

class ServiceTest < ActiveSupport::TestCase
  test "the catch-all sorts last, not alphabetically" do
    other = Service.create!(name: "Other")
    zebra = Service.create!(name: "Zebra")

    ordered = Service.fallback_last.to_a

    assert_equal other, ordered.last
    assert_operator ordered.index(zebra), :<, ordered.index(other)
  end

  test "everything else stays alphabetical" do
    Service.create!(name: "Other")
    names = Service.fallback_last.pluck(:name)

    assert_equal names[0..-2].sort, names[0..-2]
  end

  test "a service knows whether it is the catch-all" do
    assert Service.new(name: "Other").fallback?
    refute Service.new(name: "Website").fallback?
  end
end
