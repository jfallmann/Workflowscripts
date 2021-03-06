#https://dwheelerau.com/2014/02/17/how-to-use-deseq2-to-analyse-rnaseq-data/
library(DESeq2)
require(utils)
library("BiocParallel")

args <- commandArgs(trailingOnly = TRUE)

anname<-args[1]
inname<-args[2]
outdir<-args[3]
availablecores <- args[5]

register(MulticoreParam(availablecores))

anno <- as.matrix(read.table(gzfile(anname),row.names=1))
colnames(anno) <- c("condition")
anno <- as.data.frame(anno)
head(anno)
condcomb<-as.data.frame(combn(unique(anno$condition),2))[1:2,]
countData <- as.matrix(read.table(gzfile(inname),header=T,row.names=1))
#head(countData)

setwd(outdir)

#Check if names are consistent
all(rownames(anno) == colnames(countData))

#Create DESeqDataSet
dds <- DESeqDataSetFromMatrix(countData = countData,
                              colData = anno,
                              design= ~ condition)

#filter low counts
keep <- rowSums(counts(dds)) >= 10
dds <- dds[keep,]

#run for each pair of conditions
dds <- DESeq(dds, parallel=True, BPPARAM=MulticoreParam(workers=availablecores))

dds$condition
resultsNames(dds)

for (n in 1:ncol(condcomb)){

    cname=""
    cname=paste(condcomb[,n],collapse='_vs_')
    print(cname)

    tryCatch({
        res <- results(dds,contrast=c("condition",as.character(condcomb[1,n]),as.character(condcomb[2,n])), parallel=True, BPPARAM=MulticoreParam(workers=availablecores))#, name=paste(condcomb[,n],collapse='_vs_'))
                                        #sort and output
        resOrdered <- res[order(res$log2FoldChange),]
                                        #write the table to a csv file

        pdf(paste(cname,"DESeq2","plot.pdf",sep="_"))
        plotMA(res, ylim=c(-3,3))
        dev.off()
        write.table(as.data.frame(resOrdered), gzfile(paste(cname,'.csv.gz',sep="")), sep="\t")

###
                                        #Now we want to transform the raw discretely distributed counts so that we can do clustering. (Note: when you expect a large treatment effect you should actually set blind=FALSE (see https://bioconductor.org/packages/release/bioc/vignettes/DESeq2/inst/doc/DESeq2.html).
        rld<- rlogTransformation(dds, blind=TRUE)
        vsd<-varianceStabilizingTransformation(dds, blind=TRUE)

                                        #We also write the normalized counts to file
        write.table(as.data.frame(assay(rld)), gzfile(paste(cname,"DESeq2_rld.txt.gz",sep="_")), sep="\t", col.names=NA)
        write.table(as.data.frame(assay(vsd)), gzfile(paste(cname,"DESeq2_vsd.txt.gz",sep="_")), sep="\t", col.names=NA)
    }, error=function(e){cat("WARNING :",conditionMessage(e), "\n")})

}

#Here we choose blind so that the initial conditions setting does not influence the outcome, ie we want to see if the conditions cluster based purely on the individual datasets, in an unbiased way. According to the documentation, the rlogTransformation method that converts counts to log2 values is apparently better than the old varienceStabilisation method when the data size factors vary by large amounts.
par(mai=ifelse(1:4 <= 2, par('mai'), 0))
px     <- counts(dds)[,1] / sizeFactors(dds)[1]
ord    <- order(px)
ord    <- ord[px[ord]<150]
ord    <- ord[seq(1, length(ord), length=50)]
last   <- ord[length(ord)]
vstcol <- c('blue', 'black')
pdf(paste("DESeq2_VST","and_log2.pdf",sep="_"))
matplot(px[ord], cbind(assay(vsd)[, 1], log2(px))[ord, ], type='l', lty=1, col=vstcol, xlab='n', ylab='f(n)')
legend('bottomright', legend = c(expression('variance stabilizing transformation'), expression(log[2](n/s[1]))), fill=vstcol)
dev.off()

##############################
library('RColorBrewer')
library('gplots')
select <- order(rowMeans(counts(dds,normalized=TRUE)),decreasing=TRUE)[1:30]
hmcol<- colorRampPalette(brewer.pal(9, 'GnBu'))(100)
pdf(paste("DESeq2","heatmap1.pdf",sep="_"))
heatmap.2(counts(dds,normalized=TRUE)[select,], col = hmcol,
Rowv = FALSE, Colv = FALSE, scale='none',
dendrogram='none', trace='none', margin=c(10,6))
dev.off()
pdf(paste("DESeq2","heatmap2.pdf",sep="_"))
heatmap.2(assay(rld)[select,], col = hmcol,
Rowv = FALSE, Colv = FALSE, scale='none',
dendrogram='none', trace='none', margin=c(10, 6))
dev.off()
pdf(paste("DESeq2","heatmap3.pdf",sep="_"))
heatmap.2(assay(vsd)[select,], col = hmcol,
Rowv = FALSE, Colv = FALSE, scale='none',
dendrogram='none', trace='none', margin=c(10, 6))
dev.off()
#The above shows heatmaps for 30 most highly expressed genes (not necessarily the biggest fold change). The data is of raw counts (left), regularized log transformation (center) and from variance stabilizing transformation (right) and you can clearly see the effect of the transformation has by shrinking the variance so that we don’t get the squish effect shown in the left hand graph.
##############################
#Now we calculate sample to sample distances so we can make a dendrogram to look at the clustering of samples.
distsRL <- dist(t(assay(rld)))
mat<- as.matrix(distsRL)
rownames(mat) <- colnames(mat) <- with(colData(dds),condition)
#updated in latest vignette (See comment by Michael Love)
#this line was incorrect
#heatmap.2(mat, trace='none', col = rev(hmcol), margin=c(16, 16))
#From the Apr 2015 vignette
hc <- hclust(distsRL)
pdf(paste("DESeq2","heatmap_samplebysample.pdf",sep="_"))
heatmap.2(mat, Rowv=as.dendrogram(hc),
symm=TRUE, trace='none',
col = rev(hmcol), margin=c(13, 13))
dev.off()

##############################
pdf(paste("DESeq2","PCA.pdf",sep="_"))
print(plotPCA(rld, intgroup=c('condition')))
dev.off()
