# frozen_string_literal: true

require_relative "test_helper"
require "active_record"
require "tmpdir"

class SchemaGraphTest < Minitest::Test
  @@fixture_created = false

  def setup
    @tool = Ask::Ruby::Harness::Tools::SchemaGraph.new
    ensure_fixture_db
  end

  def test_defines_correct_name
    assert_equal "schema_graph", @tool.name
  end

  def test_defines_detail_param
    assert @tool.parameters.key?(:detail)
  end

  def test_inherits_from_harness_tool
    assert Ask::Ruby::Harness::Tools::SchemaGraph.ancestors.include?(Ask::Ruby::Harness::Tool)
  end

  def test_returns_hash_with_summary
    result = @tool.execute
    assert_instance_of Hash, result
    assert result.key?(:summary)
    assert_kind_of Integer, result[:summary][:model_count]
  end

  def test_all_detail_returns_all_keys
    result = @tool.execute(detail: "all")
    assert result.key?(:models)
    assert result.key?(:associations)
    assert result.key?(:tables)
  end

  def test_models_detail_returns_only_models
    result = @tool.execute(detail: "models")
    assert result[:models].is_a?(Array)
    assert_nil result[:tables]
    assert_nil result[:associations]
  end

  def test_associations_detail_returns_only_associations
    result = @tool.execute(detail: "associations")
    assert result[:associations].is_a?(Array)
    assert_nil result[:models]
  end

  def test_tables_detail_returns_only_tables
    result = @tool.execute(detail: "tables")
    assert result[:tables].is_a?(Hash)
    assert_nil result[:models]
  end

  def test_discovers_all_fixture_models
    result = @tool.execute(detail: "models")
    names = result[:models].map { |m| m[:name] }
    assert_includes names, "SchemaGraphTest::TestUser"
    assert_includes names, "SchemaGraphTest::TestPost"
    assert_includes names, "SchemaGraphTest::TestComment"
  end

  def test_columns_have_correct_types
    result = @tool.execute(detail: "models")
    user = result[:models].find { |m| m[:name] == "SchemaGraphTest::TestUser" }
    refute_nil user

    email_col = user[:columns].find { |c| c[:name] == "email" }
    refute_nil email_col
    assert_equal :string, email_col[:type]
    refute email_col[:null]

    score_col = user[:columns].find { |c| c[:name] == "score" }
    refute_nil score_col
    assert_equal :integer, score_col[:type]
    assert score_col[:null]
  end

  def test_associations_are_detected
    result = @tool.execute(detail: "associations")
    edges = result[:associations]

    assert edges.any? { |e|
      e[:from] == "SchemaGraphTest::TestUser" && e[:to] == "SchemaGraphTest::TestPost" && e[:type] == :has_many
    }, "Should detect User has_many :posts"
    assert edges.any? { |e|
      e[:from] == "SchemaGraphTest::TestPost" && e[:to] == "SchemaGraphTest::TestUser" && e[:type] == :belongs_to
    }, "Should detect Post belongs_to :user"
  end

  def test_foreign_keys_in_associations
    result = @tool.execute(detail: "associations")
    edge = result[:associations].find { |e| e[:from] == "SchemaGraphTest::TestPost" && e[:type] == :belongs_to }
    refute_nil edge
    assert edge[:foreign_key].to_s.end_with?("user_id")
  end

  def test_validators_are_detected
    result = @tool.execute(detail: "models")
    user = result[:models].find { |m| m[:name] == "SchemaGraphTest::TestUser" }
    refute_nil user
    assert user[:validators].any? { |v| v[:attribute] == "email" && v[:kind] == :presence }
  end

  def test_tables_include_indexes
    result = @tool.execute(detail: "tables")
    users_table = result[:tables].values.find { |t| t[:model] == "SchemaGraphTest::TestUser" }
    refute_nil users_table
    assert users_table[:indexes].any? { |idx| idx[:columns].include?("email") && idx[:unique] }
  end

  def test_summary_has_counts
    result = @tool.execute(detail: "all")
    assert_operator result[:summary][:model_count], :>=, 3
    assert_operator result[:summary][:table_count], :>=, 3
  end

  private

  def ensure_fixture_db
    # Only create the fixture once — reuse across tests
    return if @@fixture_created
    @@fixture_created = true

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Base.connection.create_table(:test_users, force: true) do |t|
      t.string :email, null: false
      t.string :name
      t.integer :score
      t.timestamps
    end
    ActiveRecord::Base.connection.add_index(:test_users, :email, unique: true)

    ActiveRecord::Base.connection.create_table(:test_posts, force: true) do |t|
      t.references :test_user, null: false
      t.string :title, null: false
      t.text :body
      t.timestamps
    end

    ActiveRecord::Base.connection.create_table(:test_comments, force: true) do |t|
      t.references :test_post, null: false
      t.text :content, null: false
      t.timestamps
    end

    user_class = Class.new(ActiveRecord::Base) do
      self.table_name = "test_users"
      has_many :test_posts, foreign_key: :test_user_id
      validates :email, presence: true, uniqueness: true
    end
    self.class.const_set(:TestUser, user_class) unless self.class.const_defined?(:TestUser, false)

    post_class = Class.new(ActiveRecord::Base) do
      self.table_name = "test_posts"
      belongs_to :test_user
      has_many :test_comments, foreign_key: :test_post_id
      validates :title, presence: true
    end
    self.class.const_set(:TestPost, post_class) unless self.class.const_defined?(:TestPost, false)

    comment_class = Class.new(ActiveRecord::Base) do
      self.table_name = "test_comments"
      belongs_to :test_post
      validates :content, presence: true
    end
    self.class.const_set(:TestComment, comment_class) unless self.class.const_defined?(:TestComment, false)

    [self.class::TestUser, self.class::TestPost, self.class::TestComment].each(&:table_name)
  end
end
