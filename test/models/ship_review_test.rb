require "test_helper"

class ShipReviewTest < ActiveSupport::TestCase
  setup do
    @project = projects(:one)
    @reviewer = users(:one)
  end

  test "available_for returns pending reviews with no live claim" do
    review = ShipReview.create!(project: @project, status: :pending)
    assert_includes ShipReview.available_for(@reviewer), review
  end

  test "available_for excludes reviews claimed by another reviewer" do
    other = users(:two)
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: other, claim_expires_at: 5.minutes.from_now)
    refute_includes ShipReview.available_for(@reviewer), review
  end

  test "available_for includes reviews claimed by self" do
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: @reviewer, claim_expires_at: 5.minutes.from_now)
    assert_includes ShipReview.available_for(@reviewer), review
  end

  test "available_for includes expired claims regardless of holder" do
    other = users(:two)
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: other, claim_expires_at: 1.minute.ago)
    assert_includes ShipReview.available_for(@reviewer), review
  end

  test "atomic_claim assigns reviewer and expiry" do
    review = ShipReview.create!(project: @project, status: :pending)
    claimed = ShipReview.atomic_claim!(review.id, @reviewer)
    assert claimed
    assert_equal @reviewer.id, claimed.reviewer_id
    assert claimed.claim_expires_at > Time.current
  end

  test "atomic_claim returns nil when another reviewer holds an active claim" do
    other = users(:two)
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: other, claim_expires_at: 5.minutes.from_now)
    assert_nil ShipReview.atomic_claim!(review.id, @reviewer)
  end

  test "release_all_for clears active claims for the user" do
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: @reviewer, claim_expires_at: 5.minutes.from_now)
    ShipReview.release_all_for(@reviewer)
    assert_nil review.reload.reviewer_id
    assert_nil review.claim_expires_at
  end

  test "approving the review transitions the project via AASM" do
    @project.update!(ship_status: :submitted)
    review = ShipReview.create!(project: @project, status: :pending)
    review.update!(status: :approved, reviewer: @reviewer, feedback: "looks great")
    assert_equal "approved", @project.reload.ship_status
  end

  test "returning the review sends the project back to submitted" do
    @project.update!(ship_status: :under_review)
    review = ShipReview.create!(project: @project, status: :pending)
    review.update!(status: :returned, reviewer: @reviewer, feedback: "needs work")
    assert_equal "submitted", @project.reload.ship_status
  end

  test "rejecting the review marks the project rejected" do
    @project.update!(ship_status: :under_review)
    review = ShipReview.create!(project: @project, status: :pending)
    review.update!(status: :rejected, reviewer: @reviewer, feedback: "no")
    assert_equal "rejected", @project.reload.ship_status
  end
end
