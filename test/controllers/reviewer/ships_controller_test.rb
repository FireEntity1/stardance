require "test_helper"

module Reviewer
  class ShipsControllerTest < ActionDispatch::IntegrationTest
    setup do
      Flipper.enable(:reviewer_dashboard)
      @reviewer = users(:one)
      @reviewer.grant_role!(:project_certifier) unless @reviewer.has_role?(:project_certifier)
      @project = projects(:one)
      @review = ShipReview.create!(project: @project, status: :pending)
      sign_in(@reviewer)
    end

    teardown do
      Flipper.disable(:reviewer_dashboard)
    end

    test "index returns 404 when flipper flag is off" do
      Flipper.disable(:reviewer_dashboard)
      get reviewer_ships_path
      assert_response :not_found
    end

    test "index returns 404 for users without the role" do
      @reviewer.remove_role!(:project_certifier)
      get reviewer_ships_path
      assert_response :not_found
    end

    test "index renders pending reviews for project_certifier" do
      get reviewer_ships_path
      assert_response :success
      assert_select "h1", text: "Review queue"
    end

    test "next claims an available review and redirects to show" do
      get next_reviewer_ships_path
      assert_response :redirect
      @review.reload
      assert_equal @reviewer.id, @review.reviewer_id
    end

    test "update with approved verdict transitions the project" do
      @project.update!(ship_status: :submitted)
      ShipReview.atomic_claim!(@review.id, @reviewer)
      patch reviewer_ship_path(@review), params: {
        ship_review: { status: "approved", feedback: "ship it" }
      }
      assert_redirected_to next_reviewer_ships_path
      assert_equal "approved", @project.reload.ship_status
    end

    test "update with returned verdict sends project back to submitted" do
      @project.update!(ship_status: :under_review)
      ShipReview.atomic_claim!(@review.id, @reviewer)
      patch reviewer_ship_path(@review), params: {
        ship_review: { status: "returned", feedback: "needs polish" }
      }
      assert_equal "submitted", @project.reload.ship_status
    end

    test "update fails when reviewer does not hold the claim" do
      other = users(:two)
      ShipReview.atomic_claim!(@review.id, other)
      patch reviewer_ship_path(@review), params: {
        ship_review: { status: "approved", feedback: "x" }
      }
      assert_response :forbidden
    end

  end
end
