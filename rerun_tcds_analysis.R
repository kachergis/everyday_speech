# Re-run the CDS-dependent analyses of 1_modeling.Rmd with faulty vs corrected tCDS labels.
#
# The code below does not re-implement the analyses: it extracts the relevant chunks from
# 1_modeling.Rmd and evaluates them as written, swapping only the two input files that depend on
# the tCDS classifier (everyday_cds_ods.csv and the burstiness file). It runs them in a staging
# directory so nothing in dataframes/ is overwritten.
#
# Changes needed to run the chunks today (none of them changes a result):
#   * dialect_demo_info.csv and mp_demo_info.csv are Excel files with a .csv extension, and their
#     columns are named female/race/ethnicity/age_mos_PPVT instead of Female/Race/Ethnicity/PPVT_Age.
#     They are converted into the staging directory.
#   * summarize() returning several rows per group is an error in dplyr >= 1.2; it is replaced by
#     reframe(), which is what summarize() did in the dplyr version used for the paper (1.1.3).
#   * The setup chunk is skipped (it loads stargazer and effects, which are only used for LaTeX
#     tables and effect plots); the packages the analysis chunks need are loaded here.
#
# Run from the repo root, after reclassify_tcds.py and burst_detection_v2.py:
#   Rscript rerun_tcds_analysis.R

suppressMessages({
  library(tidyverse); library(lme4); library(lmerTest); library(lubridate)
  library(zoo); library(readxl); library(knitr); library(kableExtra)
})

repo <- normalizePath(".")
stopifnot(file.exists(file.path(repo, "1_modeling.Rmd")))

# ---- staging directory: <stage>/work is the knit dir, <stage>/dataframes is '../dataframes' ----
stage <- file.path(tempdir(), "tcds_rerun_stage")
unlink(stage, recursive = TRUE)
dir.create(file.path(stage, "work"), recursive = TRUE)
dir.create(file.path(stage, "dataframes"))
for (f in c("FACT_data_cleaned.csv", "participantinfo_tp1-2.csv", "ParticipantInfo_TP2.csv"))
  file.symlink(file.path(repo, "dataframes", f), file.path(stage, "work", f))
for (f in c("dialect_demo_info.csv", "mp_demo_info.csv")) {
  read_excel(file.path(repo, "dataframes", f)) %>%
    rename(Female = female, Race = race, Ethnicity = ethnicity, PPVT_Age = age_mos_PPVT) %>%
    write.csv(file.path(stage, "work", f), row.names = FALSE)
}
file.symlink(file.path(repo, "dataframes", "everyday_ctc.csv"), file.path(stage, "dataframes", "everyday_ctc.csv"))

# ---- extract chunks from 1_modeling.Rmd by label ----
rmd <- readLines(file.path(repo, "1_modeling.Rmd"))
chunk <- function(label) {
  start <- grep(paste0("^```\\{r,? *", label, "[,}]"), rmd)
  stopifnot(length(start) == 1)
  end <- start + which(grepl("^```\\s*$", rmd[(start + 1):length(rmd)]))[1]
  rmd[(start + 1):(end - 1)]
}
run <- function(code, env) eval(parse(text = code), envir = env)

# demographics (does not depend on the classifier)
setwd(file.path(stage, "work"))
base_env <- new.env()
run(chunk("read in demographic and score info"), base_env)

# the CDS part of the 'read in LENA data' chunk (the ctc/speech parts are not needed here)
lena <- chunk("read in LENA data")
cds_code <- lena[grep("^pre_pre_cds <-", lena):length(lena)]
cds_code <- sub("summarize(percen_cds_epochs", "reframe(percen_cds_epochs", cds_code, fixed = TRUE)
stopifnot(any(grepl("reframe(percen_cds_epochs", cds_code, fixed = TRUE)))

analysis_code <- c(
  chunk("compute burstiness of cds using neurodsp measures"),
  chunk("make recording stat table"),
  chunk("model relationship between age and cds burstiness"),
  chunk("model relationship between cds burstiness and vocabulary")
)

conditions <- tribble(
  ~condition,                     ~cds_file,                              ~burst_file,
  "paper (shipped burst file)",   "everyday_cds_ods.csv",                 "burstiness_compiled_results.csv",
  "faulty labels, 3*SD",          "everyday_cds_ods.csv",                 "tcds_rerun/burstiness_faulty_labels_3sd.csv",
  "corrected labels, 3*SD",       "everyday_cds_ods_reclassified.csv",    "tcds_rerun/burstiness_corrected_labels_3sd.csv",
  "faulty labels, mean+3*SD",     "everyday_cds_ods.csv",                 "tcds_rerun/burstiness_faulty_labels_mean3sd.csv",
  "corrected labels, mean+3*SD",  "everyday_cds_ods_reclassified.csv",    "tcds_rerun/burstiness_corrected_labels_mean3sd.csv"
)

results <- list()
for (i in seq_len(nrow(conditions))) {
  cond <- conditions[i, ]
  cat("\n==", cond$condition, "\n")
  burst_path <- if (startsWith(cond$burst_file, "tcds_rerun/")) file.path(repo, cond$burst_file) else file.path(repo, "dataframes", cond$burst_file)
  # children with no bursts have no burst length/amplitude; drop them up front so baseline and
  # burst models are fit to the same rows (otherwise anova() errors). The shipped file has none.
  bursts <- read.csv(burst_path)
  n_no_bursts <- sum(is.na(bursts$mean_burst_length))
  burst_path <- file.path(stage, "dataframes", paste0("burst_", i, ".csv"))
  write.csv(filter(bursts, !is.na(mean_burst_length)), burst_path, row.names = FALSE)
  cds_path <- file.path(repo, "dataframes", cond$cds_file)
  env <- new.env(parent = base_env)
  run(sub("'../dataframes/everyday_cds_ods.csv'", deparse(cds_path), cds_code, fixed = TRUE), env)
  run(sub("'../dataframes/burstiness_compiled_results.csv'", deparse(burst_path), analysis_code, fixed = TRUE), env)

  with(env, {
    coef_row <- function(s) s$coefficients[2, ]
    results[[cond$condition]] <<- tibble(
      condition = cond$condition,
      dropped_no_bursts = n_no_bursts,
      recordings = n_distinct(burst_df2$child_id),
      children = n_distinct(burst_df2$ResearchID),
      cds_prob_mean = cds_stats$mean_cds_prob, cds_prob_sd = cds_stats$sd_cds_prob,
      pct_cds_epochs = 100 * cds_perc$mean_percen_cds,
      burst_amp_mean = mean(burst_df2$mean_burst_amplitude),
      burst_len_mean = mean(burst_df2$mean_burst_length),
      hrly_words_mean = mean(burst_df2$avg_hrly_words),
      age_amp_chisq = amp_test$Chisq[2], age_amp_p = amp_test$`Pr(>Chisq)`[2],
      age_amp_beta = coef_row(burst_amp_sum)[["Estimate"]], age_amp_beta_p = coef_row(burst_amp_sum)[["Pr(>|t|)"]],
      age_dur_chisq = duration_test$Chisq[2], age_dur_p = duration_test$`Pr(>Chisq)`[2],
      age_dur_beta = coef_row(burst_length_sum)[["Estimate"]], age_dur_beta_p = coef_row(burst_length_sum)[["Pr(>|t|)"]],
      age_quant_chisq = quant_test$Chisq[2], age_quant_p = quant_test$`Pr(>Chisq)`[2],
      vocab_n = nobs(burst_amp_v),
      vocab_amp_chisq = amp_test_v$Chisq[2], vocab_amp_p = amp_test_v$`Pr(>Chisq)`[2],
      vocab_amp_beta = coef_row(burst_amp_v_sum)[["Estimate"]], vocab_amp_beta_p = coef_row(burst_amp_v_sum)[["Pr(>|t|)"]],
      vocab_dur_chisq = duration_test_v$Chisq[2], vocab_dur_p = duration_test_v$`Pr(>Chisq)`[2],
      vocab_dur_beta = coef_row(burst_length_v_sum)[["Estimate"]], vocab_dur_beta_p = coef_row(burst_length_v_sum)[["Pr(>|t|)"]]
    )
  })
}

setwd(repo)
out <- bind_rows(results)
write.csv(out, file.path(repo, "tcds_rerun", "results.csv"), row.names = FALSE)
print(as.data.frame(out %>% mutate(across(where(is.numeric), ~ signif(.x, 4)))) %>% t())
