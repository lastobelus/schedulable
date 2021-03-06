require 'test/unit'
require 'rubygems'
require 'active_record'
require "#{File.dirname(__FILE__)}/../init"
ActiveRecord::Base.establish_connection(:adapter => 'sqlite3', :dbfile => ':memory:')

def setup_db
  ActiveRecord::Schema.define(:version => 1) do
    create_table :news_items do |t|
      t.string :type
      t.timestamp :published_at, :expired_at
    end
    create_table :admins do |t|
      t.timestamp :authorized_on, :unauthorized_on
    end

    create_table :temporal_bobs do |t|
      t.timestamp :inhered_on, :dehered_on
    end
  end
end

def teardown_db
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table)
  end
end

class NewsItem < ActiveRecord::Base; end

class ForeverNewsItem < NewsItem
  schedulable
end

class LastWeeksNewsItem < NewsItem
  schedulable :end => :expired_at
end

class Admin < ActiveRecord::Base
  schedulable :authorized_on, :unauthorized_on, :end_required => true
end

  
class SchedulableTest < Test::Unit::TestCase
  def setup
    setup_db
  end

  def teardown
    teardown_db
  end
  
  def test_generated_boolean_methods
    newer_item = ForeverNewsItem.new
    assert !newer_item.scheduled?
    assert !newer_item.published?
    
    newer_item.published_at = 10.minutes.from_now
    assert newer_item.scheduled?
    assert !newer_item.published?
    newer_item.published_at = 10.minutes.ago
    assert !newer_item.scheduled?
    assert newer_item.published?
    
    news_item = LastWeeksNewsItem.new
    assert !news_item.scheduled?
    assert !news_item.published?
    assert !news_item.expired?
    
    news_item.published_at = 10.minutes.from_now
    assert news_item.scheduled?
    assert !news_item.published?
    assert !news_item.expired?
    news_item.published_at = 10.minutes.ago
    assert !news_item.scheduled?
    assert news_item.published?
    assert !news_item.expired?
  
    news_item.expired_at = 5.minutes.from_now
    assert news_item.scheduled?(:expired_at)
    assert !news_item.expired?
    assert news_item.published?
    news_item.expired_at = 5.minutes.ago
    assert !news_item.scheduled?(:expired_at)
    assert news_item.expired?
    assert !news_item.published?
    
    admin = Admin.new
    assert !admin.scheduled?
    assert !admin.authorized?
    assert !admin.scheduled?(:unauthorized_on)
    assert !admin.unauthorized?
    
    admin.authorized_on = 2.days.from_now
    assert admin.scheduled?
    assert !admin.authorized?
    admin.authorized_on = 2.days.ago
    assert !admin.scheduled?
    assert admin.authorized?
  
    admin.unauthorized_on = 1.day.from_now
    assert admin.scheduled?(:unauthorized_on)
    assert !admin.unauthorized?
    assert admin.authorized?
    admin.unauthorized_on = 1.day.ago
    assert !admin.scheduled?(:unauthorized_on)
    assert admin.unauthorized?
    assert !admin.authorized?
  end
  
  def test_clean_slate_no_errors
    assert Admin.new.valid?
  end
  
  def test_scheduled_end_required
    news_item = LastWeeksNewsItem.new :published_at => Time.now
    assert news_item.valid?
    
    admin = Admin.new
    admin.authorized_on = Time.now
    assert !admin.valid?
    assert admin.errors.on(:unauthorized_on)
  end
  
  def test_end_must_come_after_start
    admin = Admin.new
    admin.authorized_on = 1.day.from_now
    admin.unauthorized_on = 1.day.ago
    assert !admin.valid?
    assert admin.errors.on(:unauthorized_on)
  end
  
  def test_start_required_with_end
    admin = Admin.new
    admin.unauthorized_on = 1.day.from_now
    assert !admin.valid?
    assert admin.errors.on(:unauthorized_on)
  end
  
  def test_named_scope_based_methods_work_on_old_class
    require 'mocha'
    
    real_now = Time.now
    day_ago = 1.day.ago
    two_days_ago = 2.days.ago
    three_days_ago = 3.days.ago
    four_days_ago = 4.days.ago
    tomorrow = 1.day.from_now
    
    Time.stubs(:now).returns(three_days_ago)

    eval <<-eval
    class TemporalBob < ActiveRecord::Base
      schedulable :inhered_on, :dehered_on
    end
    eval
    
    Time.stubs(:now).returns(real_now)
    
    bob_live_two = TemporalBob.create(:inhered_on => two_days_ago)
    bob_live_three = TemporalBob.create(:inhered_on => three_days_ago)
    bob_scheduled = TemporalBob.create(:inhered_on => tomorrow)
    bob_dead = TemporalBob.create(:inhered_on => three_days_ago, :dehered_on => day_ago)

    
    assert bob_live_two.inhered?
    assert bob_live_three.inhered?
    assert !bob_scheduled.inhered?
    assert !bob_dead.inhered?
    
    assert TemporalBob.scheduled.include?(bob_scheduled)
    assert !TemporalBob.scheduled.include?(bob_live_two)
    assert !TemporalBob.scheduled.include?(bob_live_three)
    assert !TemporalBob.scheduled.include?(bob_dead)

    assert TemporalBob.inhered.include?(bob_live_two)
    assert TemporalBob.inhered.include?(bob_live_three)
    assert !TemporalBob.inhered.include?(bob_scheduled)
    assert !TemporalBob.inhered.include?(bob_dead)
  end
end
