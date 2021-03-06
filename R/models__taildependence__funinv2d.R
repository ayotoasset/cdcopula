#' @export
funinv2d <- function(FUN, x1, y, x1lim, x2lim,...,
                     method = c("tabular", "iterative")[1], tol = 1e-02)
{
  ## y = f(x1, x2) -> x2
  if(tolower(method) == "tabular")
  {
    ## If the FUNNAME does not exist, create it
    set.seed(object.size(FUN))
    FUNNAME.prefix <- runif(1)
    tabular.FUNNAME <- paste(".tabular.", FUNNAME.prefix, sep = "")

    if(!exists(tabular.FUNNAME, envir = .GlobalEnv))
    {
      ## SAVING TO DISK IS REALLY SLOW
      ## Firs try to load it on disk temp R directory.
      ## tabular.PATH <- paste(tempdir(),"/" , tabular.FUNNAME, ".Rdata", sep = "")
      ## loadTry <- try(load(tabular.PATH, envir = .GlobalEnv))

      ## If does not exist or any error on load, create and save it on disk
      ## and then load it.
      ## if(is(loadTry, "try-error"))
      ##   {
      cat("Creating tabular for function inverse with tol = ", tol, "...")
      tabular <- twowaytabular(FUN = FUN, x1lim = x1lim,
                               x2lim = x2lim,tol = tol, ...)
      assign(tabular.FUNNAME, tabular, envir = .GlobalEnv)
      cat("done.\n")
      ## save(as.name(tabular.FUNNAME), file = tabular.PATH,
      ##      envir = .GlobalEnv, precheck = FALSE)
    }
    out <- funinv2d.tab(x1 = x1, y = y,
                        tabular = get(tabular.FUNNAME, envir = .GlobalEnv))
  }
  else if(tolower(method) == "iterative")
  {
    out <- funinv2d.iter(FUN = FUN, x1 = x1, y = y, x2lim = x2lim)
  }
  return(out)
}

#' @export
funinv2d.tab <- function(x1, y, tabular)
{
  ## x1 <- parRepCpl[["lambda"]]
  ## y <- parRepCpl[["tau"]]
  nObs <- length(y)

  if(length(x1) !=nObs)
  {
    stop("The input parameters should be of the same length.")
  }

  ## The dictionary look up method for x2 given x1 and y
  tol <- tabular$tol
  nGrid1 <- tabular$nGrid1
  nGrid2 <- tabular$nGrid2
  x2Grid <- tabular$x2Grid
  Mat <- tabular$Mat # The dictionary

  ## The indices for x1.
  x1IdxRaw <- x1/tol
  x1IdxFloor <- round(x1IdxRaw)

  ## Extra work to avoid under and over flow
  x1IdxFloor1 <- (x1IdxFloor < 1)
  x1IdxFloor2 <- (x1IdxFloor > nGrid1)
  if(any(x1IdxFloor1))
  {
    ## Below the lowest index
    x1IdxFloor[x1IdxFloor1] <- 1
  }
  if(any(x1IdxFloor2))
  {
    ## Above the highest index
    x1IdxFloor[x1IdxFloor2] <- nGrid1
  }

  yMatTabFloor <- Mat[x1IdxFloor, ,drop = FALSE]

  ## Find the indices of the closed values close to y's left and right side
  yTest <- matrix(y, nObs, nGrid2)
  yFloorDev0 <- -abs(yTest-yMatTabFloor)

  ## The indices of x2
  ## FIXME: This is the bottom neck of speed.
  ## a <- proc.time()
  x2FloorIdx0 <- max.col(yFloorDev0)
  ## cat("max.col:\n")
  ## print(proc.time()-a)


  ## The parallel version is not as fast as the serial version.
  ## a <- proc.time()
  ## nSubTasks <- detectCores()
  ## dataSubIdxLst <- data.partition(
  ##         nObs = nObs,
  ##         args = list(N.subsets = nSubTasks, partiMethod = "ordered"))

  ## x2FloorIdx0.Lst <- parLapply(
  ##         cl, dataSubIdxLst,
  ##         function(x, data) max.col(data[x, , drop = FALSE]),
  ##         data = yFloorDev0)

  ## x2FloorIdx0 <- unlist(x2FloorIdx0.Lst )

  ## cat("max.col (parallel):\n")
  ## print(proc.time()-a)

  ## browser()


  x2Floor0 <- x2Grid[x2FloorIdx0]

  ## Make sure the output format is same as the input
  out <- x1
  out[1:nObs] <- x2Floor0
  return(out)
}

#' @export
twowaytabular <- function(FUN, x1lim, x2lim,tol = 1e-3,
                          gridmethod = list(x1 = "linear", x2 = "cubic"), ...)
{
  ## The dictionary lookup method The input argument. We choose to use the lower and
  ## upper tail dependence because they are fixed in [0, 1] for BB7 The code is only
  ## used once during the initialization.  If need more precisions is needed , we
  ## consider using iterative way to handle the memory problem.

  gridgens <- function(xlim, gridmethod, tol)
  {
    if(tolower(gridmethod) == "linear")
    {
      out <- seq(xlim[1]+tol, xlim[2]-tol, tol)
    }
    else if (tolower(gridmethod) == "exp")
    {
      out <- exp(seq(log(xlim[1])+tol, log(xlim[2])-tol, tol))
    }
    else if (tolower(gridmethod) == "cubic")
    {
      out <- (seq((xlim[1])^(1/3)+tol, (xlim[2])^(1/3)-tol, tol))^3
    }
    else
    {
      stop("No such grid grid generating method.")
    }
    return(out)
  }

  x1Grid <- gridgens(xlim = x1lim, gridmethod = gridmethod$x1, tol = tol)
  x2Grid <- gridgens(xlim = x2lim, gridmethod = gridmethod$x2, tol = tol)

  nGrid1 <- length(x1Grid)
  nGrid2 <- length(x2Grid)

  Mat <- matrix(NA, nGrid1, nGrid2)

  ## Big table takes huge amount of memory. We split the calculation if we
  ## require a very precise table.
  ## Split the calculations
  MaxLenCurr <- round(min(nGrid1*nGrid2, 1e6)/nGrid1)
  LoopIdx <- c(seq(1, nGrid2, MaxLenCurr), nGrid2)
  LoopIdx[1] <- 0

  yIdxCurr0 <- 0

  nLoops <- length(LoopIdx)-1
  for(j in 1:nLoops)
  {
    IdxCurr0 <- LoopIdx[j]+1
    IdxCurr1 <- LoopIdx[j+1]

    x1 <- rep(x1Grid, times = IdxCurr1-IdxCurr0+1)
    x2 <- rep(x2Grid[IdxCurr0:IdxCurr1], each = nGrid1)

    Mat[, IdxCurr0:IdxCurr1] <- FUN(x1 = x1, x2 = x2, ...)
  }

  out <- list(Mat = Mat, nGrid1 = nGrid1, nGrid2 = nGrid2, x2Grid = x2Grid, tol = tol)
  return(out)
}

#' @export
funinv2d.iter <- function(FUN, x1, y, x2lim, ...)
{
  ## TODO: The max interval could not handle Inf in the uniroot function.

  ## TODO: Consider the error handle. i.e., In theory (see the Appendix in the
  ## paper) you can't have small tau with big delta (lower tail dependent) which
  ## yields non accurate root.

  ## TODO: parallel this code
  out.x2 <- x1
  parLen <- length(y)
  out.x2[1:parLen] <- NA

  for(i in 1:parLen)
  {
    yCurr <- y[i]
    x1Curr <- x1[i]
    x2Curr <- try(uniroot(function(x,...)
    {
      FUN(x1 = x1, x2 = x, y = y, ...)-y
    }, interval = x2lim, x1 = x1, y = y, ...), silent = TRUE)

    if(is(x2Curr, "try-error"))
    {
      out.x2[i] <- NA
    }
    else
    {
      out.x2[i] <- x2Curr$root
    }
  }
  return(out.x2)
}
