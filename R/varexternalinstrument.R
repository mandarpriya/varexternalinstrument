#' Replication data from Gertler and Karadi (2015).
#'
#' @name GKdata
#' @docType data
#' @references \url{https://www.aeaweb.org/articles?id=10.1257/mac.20130329}
#' @keywords data
NULL

#' Identify the impulse response for a VAR (using the VAR estimated from the vars package), using a high frequency instrument.
#'
#' @param var A varest var, or a dataframe of reduced form residuals.
#' @param instrument A list containing the data for the instrument. Should be same length as the estimation sample.
#' @param dependent Which variable in your var are you instrumenting (as a string).
#' @param p (Integer) How many lags does your var have (only needed if supplying a dataframe instead of a varest).
#'
#' @examples
#' library(vars)
#' library(varexternalinstrument)
#' data(GKdata)
#' gkvar <- VAR(GKdata[, c("logip", "logcpi", "gs1", "ebp")], p = 12, type = "const")
#' shockcol <- externalinstrument(gkvar, GKdata$ff4_tc, "gs1")
#'
#' @export
externalinstrument <- function(var, instrument, dependent, p)
  UseMethod("externalinstrument")

#' @export
externalinstrument.varest <- function(var, instrument, dependent, p) {
  res <- data.frame(stats::residuals(var))
  p <- var$p
  return(externalinstrument(res, instrument[(p+1):length(instrument)], dependent, p))
}

#' @export
externalinstrument.data.frame <- function(var, instrument, dependent, p) {
  seriesnames <- colnames(var)
  origorder <- seriesnames
  if (dependent %in% seriesnames) {
    # order dependent first
    seriesnames <- seriesnames[seriesnames != dependent]
    seriesnames <- c(dependent, seriesnames) # Order the dependent variable first
  } else {
    stop(paste("The series you are trying to instrument (", dependent, ") is not a series in the residual dataframe.", sep =""))
  }
  # Merge the instrument into the data frame
  var[, "instrument"] <- instrument

  # put together matrix of residuals
  u <- as.matrix(var[, seriesnames])

  # Now restrict to just the sample for the instrument (if necessary)
  u <- u[!is.na(var[, "instrument"]), ]

  # Useful constants
  T <- nrow(u)
  k <- ncol(u)

  # Some necessary parts of the covariance matrix
  gamma <- (1 / (T - k*p - 1)) * t(u) %*% u
  gamma_11 <- gamma[1,1]
  gamma_21 <- matrix(gamma[2:nrow(gamma), 1], c(k-1,1))
  gamma_22 <- matrix(gamma[2:nrow(gamma), 2:nrow(gamma)], c(k-1,k-1))

  # First stage regression
  firststage <- stats::lm(stats::as.formula(paste(dependent, " ~ instrument", sep = "")), var)
  var[names(stats::predict(firststage)), "fs"] <- stats::predict(firststage)

  # Now get the second-stage coefficients - this becomes the column (though we need to scale it)
  coefs <- rep(0, k)
  names(coefs) <- seriesnames
  for (i in 1:k) {
    s <- seriesnames[i]
    if (s != dependent) {
      secondstage <- stats::lm(stats::as.formula(paste(s, " ~ fs", sep = "")), var)
      coefs[i] <- secondstage$coefficients["fs"]
    } else {
      coefs[i] <- 1
    }
  }
  s21_on_s11 <- matrix(coefs[2:k], c(k-1,1))

  Q <- (s21_on_s11 * gamma_11) %*% t(s21_on_s11) - (gamma_21 %*% t(s21_on_s11) + s21_on_s11 %*% t(gamma_21)) + gamma_22

  s12s12 <- t(gamma_21 - s21_on_s11 * gamma_11) %*% solve(Q) %*% (gamma_21 - s21_on_s11 * gamma_11)

  s11_squared <- gamma_11 - s12s12

  sp <- as.numeric(sqrt(s11_squared))

  # finally, scale the coefs (the colnames are used to reorder to the original ordering)
 return( coefs[origorder])
}
