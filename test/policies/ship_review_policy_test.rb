require "test_helper"

class ShipReviewPolicyTest < Minitest::Test
  UserStub = Struct.new(:can_review_value, :id) do
    def can_review? = can_review_value
  end

  ReviewStub = Struct.new(:reviewer_id) do
  end

  def test_index_allowed_for_reviewer
    policy = ShipReviewPolicy.new(UserStub.new(true, 1), ReviewStub.new(nil))
    assert policy.index?
  end

  def test_index_denied_for_non_reviewer
    policy = ShipReviewPolicy.new(UserStub.new(false, 1), ReviewStub.new(nil))
    refute policy.index?
  end

  def test_index_denied_for_anonymous
    policy = ShipReviewPolicy.new(nil, ReviewStub.new(nil))
    refute policy.index?
  end

  def test_show_allowed_for_reviewer
    policy = ShipReviewPolicy.new(UserStub.new(true, 1), ReviewStub.new(2))
    assert policy.show?
  end

  def test_update_requires_reviewer_to_hold_claim
    user = UserStub.new(true, 1)
    held_by_user = ReviewStub.new(1)
    held_by_other = ReviewStub.new(2)

    assert ShipReviewPolicy.new(user, held_by_user).update?
    refute ShipReviewPolicy.new(user, held_by_other).update?
  end

  def test_update_denied_for_non_reviewer_even_if_claim_owner
    policy = ShipReviewPolicy.new(UserStub.new(false, 1), ReviewStub.new(1))
    refute policy.update?
  end

  def test_next_allowed_for_reviewer
    policy = ShipReviewPolicy.new(UserStub.new(true, 1), nil)
    assert policy.next?
  end

  def test_claim_allowed_for_reviewer
    policy = ShipReviewPolicy.new(UserStub.new(true, 1), ReviewStub.new(nil))
    assert policy.claim?
  end
end
