# name: discourse-private-topics
# about: Allows to automatically hide topics based on specific rules.
# version: 2.0.0
# authors: Modified by User
# meta_topic_id: 268646
# url: https://github.com/communiteq/discourse-private-topics

enabled_site_setting :private_topics_enabled

module ::DiscoursePrivateTopics
  # Cache for hidden topics
  @@hidden_topics_cache ||= Set.new

  # Function to get topics in a specific category
  def self.get_topics_in_category(category_id)
    Topic.where(category_id: category_id).pluck(:id, :pinned, :hidden, :user_id)
  end

  # Hide a topic by updating its status
  def self.hide_topic(topic_id)
    topic = Topic.find_by(id: topic_id)
    return unless topic

    topic.hidden = true
    topic.save
    @@hidden_topics_cache.add(topic_id)
    Rails.logger.info("Topic #{topic_id} hidden successfully.")
  rescue => e
    Rails.logger.error("Error hiding topic #{topic_id}: #{e.message}")
  end

  # Process topics in a category to hide them based on conditions
  def self.process_topics(category_id, excluded_topics = [])
    topics = get_topics_in_category(category_id)

    topics.each do |topic|
      topic_id, pinned, hidden, user_id = topic
      next if excluded_topics.include?(topic_id) # Skip excluded topics
      next if @@hidden_topics_cache.include?(topic_id) # Skip already hidden topics
      next if pinned || hidden # Skip pinned or already hidden topics

      hide_topic(topic_id)
    end
  end

  # Scheduled job to periodically check and hide topics
  class ::Jobs::HideTopics < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      category_id = SiteSetting.private_topics_category.to_i
      excluded_topics = SiteSetting.private_topics_excluded_topics.split(",").map(&:to_i)

      if category_id > 0
        DiscoursePrivateTopics.process_topics(category_id, excluded_topics)
      else
        Rails.logger.warn("Private topics category is not configured.")
      end
    end
  end
end

after_initialize do
  # Add setting for category and excluded topics
  SiteSetting.class_eval do
    add_setting :private_topics_category, type: :integer, default: 0
    add_setting :private_topics_excluded_topics, type: :string, default: ""
  end
end
