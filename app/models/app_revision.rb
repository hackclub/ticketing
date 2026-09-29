# The commit this build came from. The Docker build writes REVISION at image
# build time (see Dockerfile); locally we read .git directly.
class AppRevision
  REPO = ENV.fetch("GITHUB_REPO", "hackclub/ticketing").freeze
  REVISION_FILE = Rails.root.join("REVISION")

  class << self
    def sha
      @sha ||= from_file&.first || from_git || "dev"
    end

    def committed_at
      return @committed_at if defined?(@committed_at)

      @committed_at = Time.zone.parse(from_file&.second.to_s) rescue nil
    end

    def github_url
      "https://github.com/#{REPO}/commit/#{sha}" unless sha == "dev"
    end

    private

    def from_file
      return unless REVISION_FILE.exist?

      @from_file ||= REVISION_FILE.read.split("\n").map(&:strip).reject(&:empty?)
    end

    def from_git
      head = Rails.root.join(".git/HEAD")
      return unless head.exist?

      ref = head.read.strip
      return ref.first(7) unless ref.start_with?("ref: ")

      ref_path = Rails.root.join(".git", ref.delete_prefix("ref: "))
      ref_path.read.strip.first(7) if ref_path.exist?
    end
  end
end
