#' @rdname parsimony
#' @export
fitch <- function(tree, data, site = "pscore") {
  if (!inherits(data, "phyDat"))
    stop("data must be of class phyDat")
  if (any(!is.binary(tree))) stop("Tree must be binary!")
  if (inherits(tree, "multiPhylo")) {
    TL <- attr(tree, "TipLabel")
    if (!is.null(TL)) {
      data <- subset(data, TL)
      nTips <- length(TL)
      weight <- attr(data, "weight")
      nr <- attr(data, "nr")
      m <- nr * (2L * nTips - 1L)
    }
  }
  data <- prepareDataFitch(data)
  d <- attributes(data)
  data <- as.integer(data)
  attributes(data) <- d
  if (inherits(tree, "phylo")) return(fit.fitch(tree, data, site))
  else {
    if (is.null(attr(tree, "TipLabel"))) {
      tree <- unclass(tree)
      return(sapply(tree, fit.fitch, data, site))
    }
    else {
      tree <- .uncompressTipLabel(tree)
      tree <- unclass(tree)
      tree <- lapply(tree, reorder, "postorder")
      site <- ifelse(site == "pscore", 1L, 0L)
      on.exit(.C("fitch_free"))
      .C("fitch_init", as.integer(data), as.integer(nTips * nr),
        as.integer(m), as.double(weight), as.integer(nr))
      return(sapply(tree, fast.fitch, nr, site))
    }
  }
}


fit.fitch <- function(tree, data, returnData = c("pscore", "site", "data")) {
  if (is.null(attr(tree, "order")) || attr(tree, "order") ==
    "cladewise")
    tree <- reorder(tree, "postorder")
  returnData <- match.arg(returnData)
  nr <- attr(data, "nr")
  node <- tree$edge[, 1]
  edge <- tree$edge[, 2]
  weight <- attr(data, "weight")
  m <- max(tree$edge)
  q <- length(tree$tip.label)
  result <- .Call("FITCH", data[, tree$tip.label], as.integer(nr),
    as.integer(node), as.integer(edge), as.integer(length(edge)),
    as.double(weight), as.integer(m), as.integer(q))
  if (returnData == "site") return(result[[2]])
  pscore <- result[[1]]
  res <- pscore
  if (returnData == "data")
    res <- list(pscore = pscore, dat = result[[3]], site = result[[2]])
  res
}


# NNI
fnodesNew2 <- function(EDGE, nTips, nr) {
  node <- EDGE[, 1]
  edge <- EDGE[, 2]
  n <- length(node)
  m <- as.integer(max(EDGE) + 1L)
  m2 <- 2L * n
  root0 <- as.integer(node[n])
  .Call("FNALL_NNI", as.integer(nr), node, edge, as.integer(n), as.integer(m),
    as.integer(m2), as.integer(root0))
}


# SPR und bab kompakter
fnodesNew5 <- function(EDGE, nTips, nr, m = as.integer(max(EDGE) + 1L)) {
  node <- EDGE[, 1]              # in C
  edge <- EDGE[, 2]              # in C
  n <- length(node)              # in C
  m2 <- 2L * n                     # in C
  root0 <- as.integer(node[n])   # in C
  .Call("FNALL5", as.integer(nr), node, edge, as.integer(n), as.integer(m),
    as.integer(m2), as.integer(root0), PACKAGE = "phangorn")
}


#' @rdname parsimony
#' @export
random.addition <- function(data, method = "fitch") {
  label <- names(data)
  nTips <- as.integer(length(label))
  remaining <- as.integer(sample(nTips))
  tree <- structure(list(edge = structure(c(rep(nTips + 1L, 3), remaining[1:3]),
    .Dim = c(3L, 2L)), tip.label = label, Nnode = 1L), .Names =
    c("edge", "tip.label", "Nnode"), class = "phylo", order = "postorder")
  remaining <- remaining[-c(1:3)]

  if (nTips == 3L) return(tree)

  nr <- attr(data, "nr")
  storage.mode(nr) <- "integer"
#  n <- length(data) #- 1L

  data <- subset(data, select = order(attr(data, "weight"), decreasing = TRUE))
  data <- prepareDataFitch(data)
  weight <- attr(data, "weight")

  m <- nr * (2L * nTips - 2L)

  on.exit(.C("fitch_free"))
  .C("fitch_init", as.integer(data), as.integer(nTips * nr), as.integer(m),
    as.double(weight), as.integer(nr))

  storage.mode(weight) <- "double"

  for (i in remaining) {
    edge <- tree$edge[, 2]
    score <- fnodesNew5(tree$edge, nTips, nr)[edge]
    score <- .Call("FITCHTRIP3", as.integer(i), as.integer(nr),
      as.integer(edge), as.double(score), as.double(Inf))
    res <- min(score)
    nt <- which.min(score)
    tree <- addOne(tree, i, nt)
  }
  attr(tree, "pscore") <- res
  tree
}


fast.fitch <- function(tree,  nr, ps = TRUE) {
  node <- tree$edge[, 1]
  edge <- tree$edge[, 2]
  m <- max(tree$edge)
  .Call("FITCH345", as.integer(nr), as.integer(node), as.integer(edge),
    as.integer(length(edge)), as.integer(m), as.integer(ps))
}


fitch.spr <- function(tree, data) {
  nTips <- as.integer(length(tree$tip.label))
  nr <- attr(data, "nr")
  minp <- fast.fitch(tree, nr, TRUE)
  m <- max(tree$edge)
  for (i in 1:nTips) {
    treetmp <- dropTip(tree, i)
    edge <- treetmp$edge[, 2]
    #    score = fnodesNew5(treetmp$edge, nTips, nr)[edge]
    score <- .Call("FNALL6", as.integer(nr), treetmp$edge[, 1], edge,
      as.integer(m + 1L), PACKAGE = "phangorn")[edge]
    score <- .Call("FITCHTRIP3", as.integer(i), as.integer(nr),
      as.integer(edge),  as.double(score), as.double(minp))

    if (min(score) < minp) {
      nt <- which.min(score)
      tree <- addOne(treetmp, i, nt)
      minp <- min(score)
    }
  }
  root <- getRoot(tree)
  ch <- allChildren(tree)
  for (i in (nTips + 1L):m) {
    if (i != root) {
      tmp <- dropNode(tree, i, all.ch = ch)
      if (!is.null(tmp)) {
        edge <- tmp[[1]]$edge[, 2]

        blub <- fast.fitch(tmp[[2]], nr, TRUE)
        score <- .Call("FNALL6", as.integer(nr), tmp[[1]]$edge[, 1], edge,
          as.integer(m + 1L), PACKAGE = "phangorn")[edge] + blub
        #          score = fnodesNew5(tmp[[1]]$edge, nTips, nr)[edge] + blub
        score <- .Call("FITCHTRIP3", as.integer(i), as.integer(nr),
          as.integer(edge), as.double(score), as.double(minp))
        if (min(score) < minp) {
          nt <- which.min(score)
          tree <- addOneTree(tmp[[1]], tmp[[2]], nt, tmp[[3]])
          minp <- min(score)
          ch <- allChildren(tree)
        }
      }
    }
  }
  tree
}


indexNNI2 <- function(tree) {
  parent <- tree$edge[, 1]
  child <- tree$edge[, 2]

  ind <- which(child %in% parent)
  edgeMatrix <- matrix(0L, 6, length(ind))

  pvector <- integer(max(parent))
  pvector[child] <- parent
  cvector <- allChildren(tree)

  k <- 0
  for (i in ind) {
    p1 <- parent[i]
    p2 <- child[i]
    e34 <- cvector[[p2]]
    ind1 <- cvector[[p1]]
    e12 <- ind1[ind1 != p2]
    if (pvector[p1]) edgeMatrix[, k + 1] <- c(p1, e12, e34, p2, 1L)
    else edgeMatrix[, k + 1] <- c(e12, e34, p2, 0L)
    k <- k + 1
  }
  cbind(edgeMatrix[c(1, 3, 2, 4, 5, 6), ], edgeMatrix[c(1, 4, 2, 3, 5, 6), ])
}

# nr statt data uebergeben, fitchQuartet ohne weight
# weniger Speicher 2 Zeilen weinger
fitch.nni <- function(tree, data, ...) {
  nTips <- as.integer(length(tree$tip.label)) # auskommentieren?
  INDEX <- indexNNI2(tree)
  nr <- attr(data, "nr")
  weight <- attr(data, "weight")
  p0 <- fast.fitch(tree, nr)
  m <- dim(INDEX)[2]
  tmp <- fnodesNew2(tree$edge, nTips, nr)
  pscore <- .C("fitchQuartet", as.integer(INDEX), as.integer(m),
    as.integer(nr), as.double(tmp[[1]]), as.double(tmp[[2]]),
    as.double(weight), double(m))[[7]]
  swap <- 0
  candidates <- pscore < p0
  while (any(candidates)) {
    ind <- which.min(pscore)
    pscore[ind] <- Inf
    tree2 <- changeEdge(tree, INDEX[c(2, 3), ind])
    test <- fast.fitch(tree2, nr)
    if (test >= p0)
      candidates[ind] <- FALSE
    if (test < p0) {
      p0 <- test
      swap <- swap + 1
      tree <- tree2
      indi <- which(INDEX[5, ] %in% INDEX[1:5, ind])
      candidates[indi] <- FALSE
      pscore[indi] <- Inf
    }
  }
  list(tree = tree, pscore = p0, swap = swap)
}


optim.fitch <- function(tree, data, trace = 1, rearrangements = "SPR", ...) {
  if (!inherits(tree, "phylo")) stop("tree must be of class phylo")
  if (!is.binary(tree)) {
    tree <- multi2di(tree)
    attr(tree, "order") <- NULL
  }
  if (is.rooted(tree)) {
    tree <- unroot(tree)
    attr(tree, "order") <- NULL
  }
  if (is.null(attr(tree, "order")) || attr(tree, "order") == "cladewise")
    tree <- reorder(tree, "postorder")
  if (class(data)[1] != "phyDat") stop("data must be of class phyDat")

  #   stop early for n=3 or 4
  #        if(rt)tree <- ptree(tree, data)
  #    attr(tree, "pscore") <- pscore + p0
  #    tree

  rt <- FALSE

  dup_list <- NULL
  addTaxa <- FALSE
  tmp <- TRUE
  star_tree <- FALSE
  # recursive remove parsimonious uniformative sites and
  # identical sequences
  while (tmp) {
    nam <- names(data)
    data <- removeParsUninfoSites(data)
    p0 <- attr(data, "p0")
    if (attr(data, "nr") == 0) {
      star_tree <- TRUE
      break()
      tmp <- FALSE
    }
    # unique sequences
    dup <- map_duplicates(data)
    if (!is.null(dup)) {
      tree <- drop.tip(tree, dup[, 1])
      if(length(tree$tip.label) > 2) tree <- unroot(tree)
      tree <- reorder(tree, "postorder")
      dup_list <- c(list(dup), dup_list)
      addTaxa <- TRUE
      data <- subset(data, setdiff(names(data), dup[, 1]))
    }
    else break() # tmp <- FALSE
  }

  nr <- attr(data, "nr")
  nTips <- as.integer(length(tree$tip.label))
  if(nTips < 5) rearrangements <- "NNI"
  data <- subset(data, tree$tip.label, order(attr(data, "weight"),
    decreasing = TRUE))
  dat <- prepareDataFitch(data)
  weight <- attr(data, "weight")

  m <- nr * (2L * nTips - 2L)
  on.exit({
    .C("fitch_free")
    if (addTaxa) {
      if (rt) tree <- ptree(tree, data)
      for (i in seq_along(dup_list)) {
        dup <- dup_list[[i]]
        tree <- add.tips(tree, dup[, 1], dup[, 2])
      }
      tree
    }
    if(length(tree$tip.label) > 2) tree <- unroot(tree)
    attr(tree, "pscore") <- pscore + p0
    return(tree)
  })
  .C("fitch_init", as.integer(dat), as.integer(nTips * nr), as.integer(m),
    as.double(weight), as.integer(nr))

  tree$edge.length <- NULL
  swap <- 0
  iter <- TRUE
  if(nTips < 4) iter <- FALSE
  pscore <- fast.fitch(tree, nr)
  while (iter) {
    res <- fitch.nni(tree, dat, ...)
    tree <- res$tree
    if (trace > 1) cat("optimize topology: ", pscore + p0, "-->",
        res$pscore + p0, "\n")
    pscore <- res$pscore
    swap <- swap + res$swap
    if (res$swap == 0) {
      if (rearrangements == "SPR") {
        tree <- fitch.spr(tree, dat)
        psc <- fast.fitch(tree, nr)
        if (trace > 1) cat("optimize topology (SPR): ", pscore + p0, "-->",
            psc + p0, "\n")
        if (pscore < psc + 1e-6) iter <- FALSE
        pscore <- psc
      }
      else iter <- FALSE
    }
  }
  if (trace > 0) cat("Final p-score", pscore + p0, "after ", swap,
      "nni operations \n")
}

# branch and bound
getOrder <- function(x) {
  label <- names(x)
  dm <- as.matrix(dist.hamming(x, FALSE))
  ind <- as.vector(which(dm == max(dm), arr.ind = TRUE)[1, ])
  nTips <- as.integer(length(label))
  added <- ind
  remaining <- c(1:nTips)[-ind]

  tree <- structure(list(edge = structure(c(rep(nTips + 1L, 3), c(ind, 0L)),
    .Dim = c(3L, 2L)), tip.label = label, Nnode = 1L), .Names = c("edge",
    "tip.label", "Nnode"), class = "phylo", order = "postorder")

  l <- length(remaining)
  res <- numeric(l)

  nr <- attr(x, "nr")
  storage.mode(nr) <- "integer"
  n <- length(x) #- 1L

  data <- prepareDataFitch(x)
  weight <- attr(data, "weight")
  storage.mode(weight) <- "double"

  m <- nr * (2L * nTips - 2L)

  on.exit(.C("fitch_free"))
  .C("fitch_init", as.integer(data), as.integer(nTips * nr), as.integer(m),
    as.double(weight), as.integer(nr))

  for (i in seq_along(remaining)) {
    tree$edge[3, 2] <- remaining[i]
    res[i] <- fast.fitch(tree, nr)
  }
  tmp <- which.max(res)
  added <- c(added, remaining[tmp])
  remaining <- remaining[-tmp]
  tree$edge[, 2] <- added

  #    for (i in 4:(nTips - 1L)) {
  while (length(remaining) > 0) {
    edge <- tree$edge[, 2]
    score0 <- fnodesNew5(tree$edge, nTips, nr)[edge]

    l <- length(remaining)
    res <- numeric(l)
    nt <- numeric(l)
#    k <- length(added) + 1L
    for (j in 1:l) {
      score <- .Call("FITCHTRIP3", as.integer(remaining[j]),
        as.integer(nr), as.integer(edge), as.double(score0),
        as.double(Inf))
      #            score = score0[edge] + psc
      res[j] <- min(score)
      nt[j] <- which.min(score)
    }
    tmp <- which.max(res)
    added <- c(added, remaining[tmp])
    tree <- addOne(tree, remaining[tmp], nt[tmp])
    remaining <- remaining[-tmp]
  }
  added <- c(added, remaining)
  added
}


#' Branch and bound for finding all most parsimonious trees
#'
#' \code{bab} finds all most parsimonious trees.
#'
#' This implementation is very slow and depending on the data may take very
#' long time. In the worst case all (2n-5)!! possible trees have to be
#' examined. For 10 species there are already 2027025 tip-labelled unrooted
#' trees. It only uses some basic strategies to find a lower and upper bounds
#' similar to penny from phylip. It uses a very basic heuristic approach of
#' MinMax Squeeze (Holland et al. 2005) to improve the lower bound.  On the
#' positive side \code{bab} is not like many other implementations restricted
#' to binary or nucleotide data.
#'
#' @aliases bab BranchAndBound
#' @param data an object of class phyDat.
#' @param tree a phylogenetic tree an object of class phylo, otherwise a
#' pratchet search is performed.
#' @param trace defines how much information is printed during optimisation.
#' @param \dots Further arguments passed to or from other methods
#' @return \code{bab} returns all most parsimonious trees in an object of class
#' \code{multiPhylo}.
#' @author Klaus Schliep \email{klaus.schliep@@gmail.com} based on work on Liam
#' Revell
#' @seealso \code{\link{pratchet}}, \code{\link{dfactorial}}
#' @references Hendy, M.D. and Penny D. (1982) Branch and bound algorithms to
#' determine minimal evolutionary trees.  \emph{Math. Biosc.} \bold{59},
#' 277-290
#'
#' Holland, B.R., Huber, K.T. Penny, D. and Moulton, V. (2005) The MinMax
#' Squeeze: Guaranteeing a Minimal Tree for Population Data, \emph{Molecular
#' Biology and Evolution}, \bold{22}, 235--242
#'
#' White, W.T. and Holland, B.R. (2011) Faster exact maximum parsimony search
#' with XMP. \emph{Bioinformatics}, \bold{27(10)},1359--1367
#' @keywords cluster
#' @examples
#'
#' data(yeast)
#' dfactorial(11)
#' # choose only the first two genes
#' gene12 <- subset(yeast, , 1:3158, site.pattern=FALSE)
#' trees <- bab(gene12)
#'
#' @export bab
bab <- function(data, tree = NULL, trace = 1, ...) {
  if (!is.null(tree)) data <- subset(data, tree$tip.label)
  pBound <- TRUE

  nTips <- length(data)
  if (nTips < 4) return(stree(nTips, tip.label = names(data)))

  dup_list <- NULL
  addTaxa <- FALSE
  tmp <- TRUE
  star_tree <- FALSE
  while (tmp) {
    nam <- names(data)
    data <- removeParsUninfoSites(data)
    p0 <- attr(data, "p0")
    if (attr(data, "nr") == 0) {
      star_tree <- FALSE
      break()
      tmp <- FALSE
    }
    # unique sequences
    dup <- map_duplicates(data)
    if (!is.null(dup)) {
      dup_list <- c(list(dup), dup_list)
      addTaxa <- TRUE
      data <- subset(data, setdiff(names(data), dup[, 1]))
    }
    else tmp <- FALSE
  }
  # star tree
  #  if(attr(data, "nr") == 0) return(stree(nTips, tip.label = names(data)))
  nTips <- length(data)
  if (nTips < 4L  || star_tree) {
    if (star_tree) tree <- stree(length(nam), tip.label = nam)
    else tree <- stree(nTips, tip.label = names(data))
    for (i in seq_along(dup_list)) {
      dup <- dup_list[[i]]
      tree <- add.tips(tree, dup[, 1], dup[, 2])
    }
    return(tree)
  }

  # compress sequences (all transitions count equal)
  data <- compressSites(data)

  o <- order(attr(data, "weight"), decreasing = TRUE)
  data <- subset(data, select = o)

  tree <- pratchet(data, start = tree, trace = trace - 1, ...)
  data <- subset(data, tree$tip.label)
  nr <- as.integer(attr(data, "nr"))
  inord <- getOrder(data)
#  lb <- lowerBound(data)
  nTips <- m <- length(data)

  nr <- as.integer(attr(data, "nr"))
  TMP <- UB <- matrix(0, m, nr)
  for (i in 4:m) {
    TMP[i, ] <- lowerBound(subset(data, inord[1:i]))
    UB[i, ] <- upperBound(subset(data, inord[1:i]))
  }

  dat_used <- subset(data, inord)

  weight <- as.double(attr(data, "weight"))
  data <- prepareDataFitch(data)
  m <- nr * (2L * nTips - 2L)
  # spaeter
  on.exit(.C("fitch_free"))
  .C("fitch_init", as.integer(data), as.integer(nTips * nr), as.integer(m),
    as.double(weight), as.integer(nr))
  mmsAmb <- 0
  mmsAmb <- TMP %*% weight
  mmsAmb <- mmsAmb[nTips] - mmsAmb
  mms0 <- 0
  if (pBound) mms0 <- pBound(dat_used, UB)
  mms0 <- mms0 + mmsAmb

  minPars <- mms0[1]
  kPars <- 0

  if (trace)
    print(paste("lower bound:", p0 + mms0[1]))
  bound <- fast.fitch(tree, nr)
  if (trace)
    print(paste("upper bound:", bound + p0))

  startTree <- structure(list(edge = structure(c(rep(nTips + 1L, 3),
    as.integer(inord)[1:3]), .Dim = c(3L, 2L)), tip.label = tree$tip.label,
  Nnode = 1L), .Names = c("edge", "tip.label", "Nnode"), class = "phylo",
  order = "postorder")

  trees <- vector("list", nTips)
  trees[[3]] <- list(startTree$edge)
  for (i in 4:nTips) trees[[i]] <- vector("list", (2L * i) - 5L) # new

  # index M[i] is neues node fuer edge i+1
  # index L[i] is length(node) tree mit i+1
  L <- as.integer(2L * (1L:nTips) - 3L)
  M <- as.integer(1L:nTips + nTips - 1L)

  PSC <- matrix(c(3, 1, 0), 1, 3)
  PSC[1, 3] <- fast.fitch(startTree, nr)

  k <- 4L
  Nnode <- 1L
  npsc <- 1

  blub <- numeric(nTips)

  result <- list()
  while (npsc > 0) {
    a <- PSC[npsc, 1]
    b <- PSC[npsc, 2]
    PSC <- PSC[-npsc, , drop = FALSE]
    npsc <- npsc - 1L
    tmpTree <- trees[[a]][[b]]
    edge <- tmpTree[, 2]
    score <- fnodesNew5(tmpTree, nTips, nr, M[a])[edge] + mms0[a + 1L]
    score <- .Call("FITCHTRIP3", as.integer(inord[a + 1L]), as.integer(nr),
      as.integer(edge), as.double(score), as.double(bound),
      PACKAGE = "phangorn")

    ms <- min(score)
    if (ms <= bound) {
      if ((a + 1L) < nTips) {
        ind <- (1:L[a])[score <= bound]
        trees[[a + 1]][seq_along(ind)] <- .Call("AddOnes", tmpTree,
          as.integer(inord[a + 1L]), as.integer(ind), as.integer(L[a]),
          as.integer(M[a]), PACKAGE = "phangorn")
        l <- length(ind)
        # os <- order(score[ind], decreasing=TRUE)
        os <- seq_len(l)
        # in C pushback
        PSC <- rbind(PSC, cbind(rep(a + 1, l), os, score[ind]))
        npsc <- npsc + l
        blub[a] <- blub[a] + l
        #  PSC = rbind(PSC, cbind(rep(a+1, l), os, score[ind][os] ))
      }
      else {
        ind <- which(score == ms)
        tmp <- vector("list", length(ind))
        tmp[seq_along(ind)] <- .Call("AddOnes", tmpTree,
          as.integer(inord[a + 1L]), as.integer(ind),
          as.integer(L[a]), as.integer(M[a]), PACKAGE = "phangorn")
        if (ms < bound) {
          bound <- ms
          if (trace) cat("upper bound:", bound + p0, "\n")
          result <- tmp
          PSC <- PSC[PSC[, 3] < (bound + 1e-8), ]
          npsc <- nrow(PSC)
        }
        else result <- c(result, tmp)
      }
    }
  }
  for (i in seq_along(result)) {
    result[[i]] <- structure(list(edge = result[[i]], Nnode = nTips - 2L),
      .Names = c("edge", "Nnode"), class = "phylo", order = "postorder")
  }
  attr(result, "TipLabel") <- tree$tip.label
  #    attr(result, "visited") = blub
  class(result) <- "multiPhylo"
  if (addTaxa) {
    result <- .uncompressTipLabel(result)
    class(result) <- NULL
    for (i in seq_along(dup_list)) {
      dup <- dup_list[[i]]
      result <- lapply(result, add.tips, dup[, 1], dup[, 2])
    }
    class(result) <- "multiPhylo"
    result <- .compressTipLabel(result)
  }
  return(result)
}


pBound <- function(x, UB) {
  tip <- names(x)
  att <- attributes(x)
  nc <- attr(x, "nc")
  nr <- attr(x, "nr")
  contrast <- attr(x, "contrast")
  rownames(contrast) <- attr(x, "allLevels")
  colnames(contrast) <- attr(x, "levels")
  weight0 <- attr(x, "weight")
  attr(x, "weight") <- rep(1, nr)
  attr(x, "index") <- NULL

  y <- as.character(x)
  #    states <- apply(y, 2, unique.default)
  #    singles <- match(attr(x, "levels"), attr(x, "allLevels"))
  singles <- attr(x, "levels")
  fun2 <- function(x, singles) all(x %in% singles)

  fun1 <- function(x) {cumsum(!duplicated(x)) - 1L}

  tmp <- apply(y, 2, fun2, singles)
  ind <- which(tmp)
  if (length(ind) < 2) return(numeric(nTips))

  y <- y[, ind, drop = FALSE]
  weight0 <- weight0[ind]

  UB <- UB[, ind, drop = FALSE]
  single_dis <- apply(y, 2, fun1)
  # single_dis <- lowerBound

  nTips <- nrow(y)
  l <- length(weight0)

  res <- numeric(nTips)

  for (i in 1:(l - 1)) {
    for (j in (i + 1):l) {
      #            cat(i, j, "\n")
      if ((weight0[i] > 0) & (weight0[j] > 0)) {
        z <- paste(y[, i], y[, j], sep = "_")
        dis2 <- single_dis[, i] + single_dis[, j]
        #                D1 <- (dis2[nTips] - dis2)
        dis <- fun1(z)
        #                dis <- pmax(dis, dis2)
        #                D2 <- dis[nTips] - (UB[, i] + UB[, j])
        if (dis[nTips] > dis2[nTips]) {

          ub <- UB[, i] + UB[, j]
          dis <- dis[nTips] - ub
          d2 <- dis2[nTips] - dis2
          dis <- pmax(dis, d2) - d2

          if (sum(dis[4:nTips]) > 0) {
            wmin <- min(weight0[i], weight0[j])
            weight0[i] <- weight0[i] - wmin
            weight0[j] <- weight0[j] - wmin
            res <- res + dis * wmin
          }
        }
      }
      if(weight0[i] < 1e-6) break()
    }
  }
  res
}
