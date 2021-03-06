## Wrappers for Salmon quantification of abundance of RNA-seq reads


################################################################################
#' Read Salmon results for a single sample into a list
#' 
#' @param directory character string giving the path to the directory containing
#' the Salmon results for the sample. 
#' 
#' @details The directory is expected to contain results for just a single 
#' sample. Putting more than one sample's results in the directory will result
#' in unpredictable behaviour with this function. The function looks for the 
#' files (with the default names given by Salmon) 'quant.sf', 
#' 'stats.tsv', 'libFormatCounts.txt' and the sub-directories 'logs' (which 
#' contains a log file) and 'libParams' (which contains a file detailing the 
#' fragment length distribution). If these files are missing, or if results 
#' files have different names, then this function will not find them. 
#' 
#' @return A list with two elements: (1) a data.frame \code{abundance} with 
#' columns for 'target_id' (feature, transcript, gene etc), 'length' (feature 
#' length), 'est_counts' (estimated feature counts), 'tpm' (transcripts per 
#' million) and possibly many columns containing bootstrap estimated counts; 
#' and (2) a list \code{run_info} with details about the Salmon run that 
#' generated the results.
#' 
#' @export
#' @examples
#' \dontrun{
#' # If Salmon results are in the directory "output", then call:
#' readSalmonResultsOneSample("output")
#' }
readSalmonResultsOneSample <- function(directory) {
    ## Read in abundance information for the sample
    file_to_read <- paste0(directory, "/quant.sf")
    abundance <- run_info <- NULL
    if ( file.exists(file_to_read) ) {
        ## read abundance values
        abundance <- data.table::fread(file_to_read, sep = "\t")
        abundance <- as.data.frame(abundance)
        colnames(abundance) <- c("target_id", "length", "eff_length", "tpm", "est_counts")
        abundance <- abundance[, c(1, 2, 3, 5, 4)]
        ## extract run info
        json_file <- paste0(directory, "/aux/meta_info.json")
        if(!file.exists(json_file)) stop(paste(json_file, "not found or does not exist."))
        run_info <- as.data.frame(rjson::fromJSON(file = json_file))
    }
    else
        stop(paste("File", file_to_read, "not found or does not exist. 
                   Please check directory is correct."))
    ## output list with abundances and run info
    list(abundance = abundance, run_info = run_info)
}


################################################################################
#' Read Salmon results from a batch of jobs 
#' 
#' After generating transcript/feature abundance results using Salmon for a 
#' batch of samples, read these abundance values into an \code{SCESet} object.
#' 
#' @param Salmon_log list, generated by \code{runSalmon}. If provided, then 
#' \code{samples} and \code{directories} arguments are ignored.
#' @param samples character vector providing a set of sample names to use for 
#' the abundance results.
#' @param directories character vector providing a set of directories containing
#' Salmon abundance results to be read in.
#' @param logExprsOffset numeric scalar, providing the offset used when doing
#' log2-transformations of expression data to avoid trying to take logs of zero.
#' Default offset value is \code{1}.
#' @param verbose logical, should function provide output about progress?
#' 
#' @details This function expects to find only one set of Salmon abundance 
#' results per directory; multiple adundance results in a given directory will 
#' be problematic.
#' 
#' @return an SCESet object
#' 
#' @export
#' @examples
#' \dontrun{
#' ## Define output directories in a vector called here "Salmon_dirs"
#' ## and sample names as "Salmon_samples"
#' sceset <- readSalmonResults(samples = Salmon_samples, 
#' directories = Salmon_dirs)
#' }
#' 
readSalmonResults <- function(Salmon_log = NULL, samples = NULL, 
                              directories = NULL, logExprsOffset = 1, 
                              verbose = TRUE) {
    ## initialise failure vector
    Salmon_fail <- rep(FALSE, length(samples))
    ## Checks on arguments
    if ( !is.null(Salmon_log) ) {
        cat("Using Salmon_log argument to define samples and results directories.")
        if ( !is.list(Salmon_log) )
            stop("The Salmon_log argument should be a list returned by runSalmon()")
        samples <- names(Salmon_log)       
        directories <- sapply(Salmon_log, function(x) {x$output_dir})
        logs <- lapply(Salmon_log, function(x) {x$Salmon_log})
        ## Can only check Salmon fail if log provided
        Salmon_fail <- sapply(logs, function(x) {
            any(grepl("[wW]arning|[eE]rror", x))})
        if ( any(Salmon_fail) ) {
            warning(paste0("The Salmon job failed for the following samples:\n ",
                           paste0(names(logs)[Salmon_fail], collapse = "\n"),
                           "\n It is recommended that you inspect Salmon_log for these samples."))
        }
        
    } else {
        cat("Salmon log not provided - assuming all runs successful")
        if ( is.null(samples) | is.null(directories) )
            stop("If Salmon_log argument is not used, then both samples and directories must be provided.")
        if ( length(samples) != length(directories) )
            stop("samples and directories arguments must be the same length")
    }
    
    samples <- samples[!Salmon_fail]
    directories <- directories[!Salmon_fail]
    
    ## Read first file to get size of feature set
    s1 <- readSalmonResultsOneSample(directories[1])
    nsamples <- length(samples)
    nfeatures <- nrow(s1$abundance)
    ninfo_vars <- ncol(s1$run_info)
    ## Currently not reading in bootstrap results - to add in future
    
    ## Set up results objects
    pdata <- data.frame(matrix(NA, nrow = nsamples, ncol = ninfo_vars))
    rownames(pdata) <- samples
    colnames(pdata) <- colnames(s1$run_info)
    fdata <- data.frame(feature_id = s1$abundance$target_id, 
                        feature_length = s1$abundance$length)
    rownames(fdata) <- s1$abundance$target_id
    est_counts <- tpm <- matrix(NA, nrow = nfeatures, ncol = nsamples)
    colnames(est_counts) <- colnames(tpm) <- samples
    rownames(est_counts) <- rownames(tpm) <- s1$abundance$target_id
    
    ## Read Salmon results into results objects
    if ( verbose )
        cat(paste("\nReading results for", nsamples, "samples:\n"))
    for (i in seq_len(nsamples)) {
        tmp_samp <- readSalmonResultsOneSample(directories[i])
        ## counts
        if ( length(tmp_samp$abundance$est_counts) != nfeatures )
            warning(paste("Results for directory", directories[i], 
                          "do not match dimensions of other samples."))
        else            
            est_counts[, i] <- tmp_samp$abundance$est_counts
        ## tpm
        if ( length(tmp_samp$abundance$est_counts) == nfeatures )
            tpm[, i] <- tmp_samp$abundance$tpm
        ## run info
        pdata[i, ] <- tmp_samp$run_info
        ## in future, add code to read in bootstraps
        if ( verbose ) {
            cat(".")
            if ( i %% 80 == 0)
                cat("\n")
        }
    }
    if ( verbose )
        cat("\n")
    ## Produce SCESet object
    pdata <- new("AnnotatedDataFrame", pdata)
    fdata <- new("AnnotatedDataFrame", fdata)
    sce_out <- newSCESet(exprsData = log2(tpm + logExprsOffset), 
                         phenoData = pdata, featureData = fdata, 
                         countData = est_counts, 
                         logExprsOffset = logExprsOffset, 
                         lowerDetectionLimit = 0)
    tpm(sce_out) <- tpm
    if ( verbose )
        cat("Using log2(TPM + 1) as 'exprs' values in output.")
    ## Return SCESet object
    sce_out
}


