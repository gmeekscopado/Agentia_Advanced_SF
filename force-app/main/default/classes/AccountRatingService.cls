/**
 * AccountRatingService
 *
 * Evaluates an Account's rating based on AnnualRevenue and NumberOfEmployees.
 * Uses a Custom Label for the threshold warning message surfaced to end users
 * and in system logs. This label is managed separately in the labels metadata.
 *
 * DEPENDENCY: CustomLabel -> Account_Rating_Threshold_Message
 * WARNING: If the value of Account_Rating_Threshold_Message is changed in another
 * branch without coordinating this class, runtime messages will be inconsistent.
 */
public with sharing class AccountRatingService {

    // Score thresholds that determine account rating tier
    private static final Integer HOT_THRESHOLD  = 8;
    private static final Integer WARM_THRESHOLD = 4;

    // Points assigned per revenue band
    private static final Integer HIGH_REVENUE_POINTS   = 4;
    private static final Integer MEDIUM_REVENUE_POINTS = 2;
    private static final Integer LOW_REVENUE_POINTS    = 1;

    // Points assigned per employee band
    private static final Integer LARGE_EMPLOYEE_POINTS  = 4;
    private static final Integer MEDIUM_EMPLOYEE_POINTS = 2;
    private static final Integer SMALL_EMPLOYEE_POINTS  = 1;

    /**
     * Calculates and assigns a rating (Hot / Warm / Cold) to each Account.
     * Reads the threshold warning label to produce a user-facing advisory when
     * an account's score sits exactly on a boundary.
     *
     * @param accounts  List of Account records to evaluate (bulk-safe).
     */
    public static void calculateRatings(List<Account> accounts) {
        // Retrieve the label once outside the loop to respect governor limits
        String thresholdMessage = Label.Account_Rating_Threshold_Message;

        for (Account acc : accounts) {
            Integer score = 0;

            // --- Revenue scoring ---
            if (acc.AnnualRevenue != null) {
                if (acc.AnnualRevenue >= 1000000) {
                    score += HIGH_REVENUE_POINTS;
                } else if (acc.AnnualRevenue >= 500000) {
                    score += MEDIUM_REVENUE_POINTS;
                } else {
                    score += LOW_REVENUE_POINTS;
                }
            }

            // --- Employee count scoring ---
            if (acc.NumberOfEmployees != null) {
                if (acc.NumberOfEmployees >= 500) {
                    score += LARGE_EMPLOYEE_POINTS;
                } else if (acc.NumberOfEmployees >= 100) {
                    score += MEDIUM_EMPLOYEE_POINTS;
                } else {
                    score += SMALL_EMPLOYEE_POINTS;
                }
            }

            // --- Opportunity count scoring (queried separately by caller if needed) ---
            // Reserved for future expansion

            // --- Assign rating tier ---
            if (score >= HOT_THRESHOLD) {
                acc.Rating = 'Hot';
            } else if (score >= WARM_THRESHOLD) {
                acc.Rating = 'Warm';
                // Surface advisory to logs when score is at the boundary
                if (score == WARM_THRESHOLD) {
                    System.debug(LoggingLevel.WARN,
                        '[AccountRatingService] Boundary score detected. ' +
                        'Advisory: ' + thresholdMessage +
                        ' | Account: ' + acc.Name +
                        ' | Score: ' + score);
                }
            } else {
                acc.Rating = 'Cold';
            }
        }
    }
}
