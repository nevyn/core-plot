#import "CPTPlot.h"

#import "CPTExceptions.h"
#import "CPTFill.h"
#import "CPTGraph.h"
#import "CPTLegend.h"
#import "CPTLineStyle.h"
#import "CPTMutableNumericData+TypeConversion.h"
#import "CPTMutableNumericData.h"
#import "CPTMutablePlotRange.h"
#import "CPTNumericData+TypeConversion.h"
#import "CPTNumericData.h"
#import "CPTPathExtensions.h"
#import "CPTPlotArea.h"
#import "CPTPlotAreaFrame.h"
#import "CPTPlotSpace.h"
#import "CPTPlotSpaceAnnotation.h"
#import "CPTTextLayer.h"
#import "CPTUtilities.h"
#import "NSCoderExtensions.h"
#import "NSNumberExtensions.h"
#import <tgmath.h>

/**	@defgroup plotAnimation Plots
 *	@brief Plot properties that can be animated using Core Animation.
 *	@if MacOnly
 *	@since Custom layer property animation is supported on MacOS 10.6 and later.
 *	@endif
 *	@ingroup animation
 **/

/**	@defgroup plotAnimationAllPlots All Plots
 *	@ingroup plotAnimation
 **/

/**	@if MacOnly
 *	@defgroup plotBindings Plot Binding Identifiers
 *	@endif
 **/

///	@cond
@interface CPTPlot()

@property (nonatomic, readwrite, assign) BOOL dataNeedsReloading;
@property (nonatomic, readwrite, retain) NSMutableDictionary *cachedData;

@property (nonatomic, readwrite, assign) BOOL needsRelabel;
@property (nonatomic, readwrite, assign) NSRange labelIndexRange;
@property (nonatomic, readwrite, retain) NSMutableArray *labelAnnotations;

@property (nonatomic, readwrite, assign) NSUInteger cachedDataCount;

-(CPTMutableNumericData *)numericDataForNumbers:(id)numbers;
-(void)setCachedDataType:(CPTNumericDataType)newDataType;
-(void)updateContentAnchorForLabel:(CPTPlotSpaceAnnotation *)label;

@end

///	@endcond

#pragma mark -

/**	@brief An abstract plot class.
 *
 *	Each data series on the graph is represented by a plot. Data is provided by
 *	a datasource that conforms to the CPTPlotDataSource protocol.
 *	@if MacOnly
 *	Plots also support data binding on MacOS.
 *	@endif
 *
 *	A Core Plot plot will request its data from the datasource when it is first displayed.
 *	You can force it to load new data in several ways:
 *	- Call @link CPTGraph::reloadData -reloadData @endlink on the graph to reload all plots.
 *	- Call @link CPTPlot::reloadData -reloadData @endlink on the plot to reload all of the data for only that plot.
 *	- Call @link CPTPlot::reloadDataInIndexRange: -reloadDataInIndexRange: @endlink on the plot to reload a range
 *	  of data indices without changing the total number of data points.
 *	- Call @link CPTPlot::insertDataAtIndex:numberOfRecords: -insertDataAtIndex:numberOfRecords: @endlink
 *	  to insert new data at the given index. Any data at higher indices will be moved to make room.
 *	  Only the new data will be requested from the datasource.
 *
 *	You can also remove data from the plot without reloading anything by using the
 *	@link CPTPlot::deleteDataInIndexRange: -deleteDataInIndexRange: @endlink method.
 *
 *	@see See @ref plotAnimation "Plots" for a list of animatable properties supported by each plot type.
 *	@if MacOnly
 *	@see See @ref plotBindings "Plot Bindings" for a list of binding identifiers supported by each plot type.
 *	@endif
 **/
@implementation CPTPlot

/**	@property dataSource
 *	@brief The data source for the plot.
 **/
@synthesize dataSource;

/**	@property title
 *	@brief The title of the plot displayed in the legend.
 **/
@synthesize title;

/**	@property plotSpace
 *	@brief The plot space for the plot.
 **/
@synthesize plotSpace;

/**	@property plotArea
 *	@brief The plot area for the plot.
 **/
@dynamic plotArea;

/**	@property dataNeedsReloading
 *	@brief If YES, the plot data will be reloaded from the data source before the layer content is drawn.
 **/
@synthesize dataNeedsReloading;

@synthesize cachedData;

/**	@property cachedDataCount
 *	@brief The number of data points stored in the cache.
 **/
@synthesize cachedDataCount;

/**	@property doublePrecisionCache
 *	@brief If YES, the cache holds data of type 'double', otherwise it holds NSDecimal.
 **/
@dynamic doublePrecisionCache;

/**	@property cachePrecision
 *	@brief The numeric precision used to cache the plot data and perform all plot calculations. Defaults to #CPTPlotCachePrecisionAuto.
 **/
@synthesize cachePrecision;

/**	@property doubleDataType
 *	@brief The CPTNumericDataType used to cache plot data as <code>double</code>.
 **/
@dynamic doubleDataType;

/**	@property decimalDataType
 *	@brief The CPTNumericDataType used to cache plot data as NSDecimal.
 **/
@dynamic decimalDataType;

/**	@property needsRelabel
 *	@brief If YES, the plot needs to be relabeled before the layer content is drawn.
 **/
@synthesize needsRelabel;

/**	@property labelOffset
 *	@brief The distance that labels should be offset from their anchor points. The direction of the offset is defined by subclasses.
 *	@ingroup plotAnimationAllPlots
 **/
@synthesize labelOffset;

/**	@property labelRotation
 *	@brief The rotation of the data labels in radians.
 *  Set this property to <code>M_PI/2.0</code> to have labels read up the screen, for example.
 *	@ingroup plotAnimationAllPlots
 **/
@synthesize labelRotation;

/**	@property labelField
 *	@brief The plot field identifier of the data field used to generate automatic labels.
 **/
@synthesize labelField;

/**	@property labelTextStyle
 *	@brief The text style used to draw the data labels.
 *	Set this property to <code>nil</code> to hide the data labels.
 **/
@synthesize labelTextStyle;

/**	@property labelFormatter
 *	@brief The number formatter used to format the data labels.
 *	Set this property to <code>nil</code> to hide the data labels.
 *  If you need a non-numerical label, such as a date, you can use a formatter than turns
 *  the numerical plot coordinate into a string (e.g., "Jan 10, 2010").
 *  The CPTTimeFormatter is useful for this purpose.
 **/
@synthesize labelFormatter;

/**	@property labelShadow
 *	@brief The shadow applied to each data label.
 **/
@synthesize labelShadow;

@synthesize labelIndexRange;

@synthesize labelAnnotations;

/**	@property alignsPointsToPixels
 *	@brief If YES (the default), all plot points will be aligned to device pixels when drawing.
 **/
@synthesize alignsPointsToPixels;

#pragma mark -
#pragma mark init/dealloc

/// @name Initialization
/// @{

/** @brief Initializes a newly allocated CPTPlot object with the provided frame rectangle.
 *
 *	This is the designated initializer. The initialized layer will have the following properties:
 *	- @link CPTPlot::cachedDataCount cachedDataCount @endlink = 0
 *	- @link CPTPlot::cachePrecision cachePrecision @endlink = #CPTPlotCachePrecisionAuto
 *	- @link CPTPlot::dataSource dataSource @endlink = <code>nil</code>
 *	- @link CPTPlot::title title @endlink = <code>nil</code>
 *	- @link CPTPlot::plotSpace plotSpace @endlink = <code>nil</code>
 *	- @link CPTPlot::dataNeedsReloading dataNeedsReloading @endlink = <code>NO</code>
 *	- @link CPTPlot::needsRelabel needsRelabel @endlink = <code>YES</code>
 *	- @link CPTPlot::labelOffset labelOffset @endlink = 0.0
 *	- @link CPTPlot::labelRotation labelRotation @endlink = 0.0
 *	- @link CPTPlot::labelField labelField @endlink = 0
 *	- @link CPTPlot::labelTextStyle labelTextStyle @endlink = <code>nil</code>
 *	- @link CPTPlot::labelFormatter labelFormatter @endlink = <code>nil</code>
 *	- @link CPTPlot::labelShadow labelShadow @endlink = <code>nil</code>
 *	- @link CPTPlot::alignsPointsToPixels alignsPointsToPixels @endlink = <code>YES</code>
 *	- <code>masksToBounds</code> = <code>YES</code>
 *	- <code>needsDisplayOnBoundsChange</code> = <code>YES</code>
 *
 *	@param newFrame The frame rectangle.
 *  @return The initialized CPTPlot object.
 **/
-(id)initWithFrame:(CGRect)newFrame
{
    if ( (self = [super initWithFrame:newFrame]) ) {
        cachedData           = [[NSMutableDictionary alloc] initWithCapacity:5];
        cachedDataCount      = 0;
        cachePrecision       = CPTPlotCachePrecisionAuto;
        dataSource           = nil;
        title                = nil;
        plotSpace            = nil;
        dataNeedsReloading   = NO;
        needsRelabel         = YES;
        labelOffset          = 0.0;
        labelRotation        = 0.0;
        labelField           = 0;
        labelTextStyle       = nil;
        labelFormatter       = nil;
        labelShadow          = nil;
        labelIndexRange      = NSMakeRange(0, 0);
        labelAnnotations     = nil;
        alignsPointsToPixels = YES;

        self.masksToBounds              = YES;
        self.needsDisplayOnBoundsChange = YES;
    }
    return self;
}

///	@}

-(id)initWithLayer:(id)layer
{
    if ( (self = [super initWithLayer:layer]) ) {
        CPTPlot *theLayer = (CPTPlot *)layer;

        cachedData           = [theLayer->cachedData retain];
        cachedDataCount      = theLayer->cachedDataCount;
        cachePrecision       = theLayer->cachePrecision;
        dataSource           = theLayer->dataSource;
        title                = [theLayer->title retain];
        plotSpace            = [theLayer->plotSpace retain];
        dataNeedsReloading   = theLayer->dataNeedsReloading;
        needsRelabel         = theLayer->needsRelabel;
        labelOffset          = theLayer->labelOffset;
        labelRotation        = theLayer->labelRotation;
        labelField           = theLayer->labelField;
        labelTextStyle       = [theLayer->labelTextStyle retain];
        labelFormatter       = [theLayer->labelFormatter retain];
        labelShadow          = [theLayer->labelShadow retain];
        labelIndexRange      = theLayer->labelIndexRange;
        labelAnnotations     = [theLayer->labelAnnotations retain];
        alignsPointsToPixels = theLayer->alignsPointsToPixels;
    }
    return self;
}

-(void)dealloc
{
    [cachedData release];
    [title release];
    [plotSpace release];
    [labelTextStyle release];
    [labelFormatter release];
    [labelShadow release];
    [labelAnnotations release];

    [super dealloc];
}

#pragma mark -
#pragma mark NSCoding methods

-(void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if ( [self.dataSource conformsToProtocol:@protocol(NSCoding)] ) {
        [coder encodeConditionalObject:self.dataSource forKey:@"CPTPlot.dataSource"];
    }
    [coder encodeObject:self.title forKey:@"CPTPlot.title"];
    [coder encodeObject:self.plotSpace forKey:@"CPTPlot.plotSpace"];
    [coder encodeInteger:self.cachePrecision forKey:@"CPTPlot.cachePrecision"];
    [coder encodeBool:self.needsRelabel forKey:@"CPTPlot.needsRelabel"];
    [coder encodeCGFloat:self.labelOffset forKey:@"CPTPlot.labelOffset"];
    [coder encodeCGFloat:self.labelRotation forKey:@"CPTPlot.labelRotation"];
    [coder encodeInteger:self.labelField forKey:@"CPTPlot.labelField"];
    [coder encodeObject:self.labelTextStyle forKey:@"CPTPlot.labelTextStyle"];
    [coder encodeObject:self.labelFormatter forKey:@"CPTPlot.labelFormatter"];
    [coder encodeObject:self.labelShadow forKey:@"CPTPlot.labelShadow"];
    [coder encodeObject:[NSValue valueWithRange:self.labelIndexRange] forKey:@"CPTPlot.labelIndexRange"];
    [coder encodeObject:self.labelAnnotations forKey:@"CPTPlot.labelAnnotations"];
    [coder encodeBool:self.alignsPointsToPixels forKey:@"CPTPlot.alignsPointsToPixels"];

    // No need to archive these properties:
    // dataNeedsReloading
    // cachedData
    // cachedDataCount
}

-(id)initWithCoder:(NSCoder *)coder
{
    if ( (self = [super initWithCoder:coder]) ) {
        dataSource           = [coder decodeObjectForKey:@"CPTPlot.dataSource"];
        title                = [[coder decodeObjectForKey:@"CPTPlot.title"] copy];
        plotSpace            = [[coder decodeObjectForKey:@"CPTPlot.plotSpace"] retain];
        cachePrecision       = [coder decodeIntegerForKey:@"CPTPlot.cachePrecision"];
        needsRelabel         = [coder decodeBoolForKey:@"CPTPlot.needsRelabel"];
        labelOffset          = [coder decodeCGFloatForKey:@"CPTPlot.labelOffset"];
        labelRotation        = [coder decodeCGFloatForKey:@"CPTPlot.labelRotation"];
        labelField           = [coder decodeIntegerForKey:@"CPTPlot.labelField"];
        labelTextStyle       = [[coder decodeObjectForKey:@"CPTPlot.labelTextStyle"] copy];
        labelFormatter       = [[coder decodeObjectForKey:@"CPTPlot.labelFormatter"] retain];
        labelShadow          = [[coder decodeObjectForKey:@"CPTPlot.labelShadow"] retain];
        labelIndexRange      = [[coder decodeObjectForKey:@"CPTPlot.labelIndexRange"] rangeValue];
        labelAnnotations     = [[coder decodeObjectForKey:@"CPTPlot.labelAnnotations"] mutableCopy];
        alignsPointsToPixels = [coder decodeBoolForKey:@"CPTPlot.alignsPointsToPixels"];

        // support old archives
        if ( [coder containsValueForKey:@"CPTPlot.identifier"] ) {
            self.identifier = [coder decodeObjectForKey:@"CPTPlot.identifier"];
        }

        // init other properties
        cachedData         = [[NSMutableDictionary alloc] initWithCapacity:5];
        cachedDataCount    = 0;
        dataNeedsReloading = YES;
    }
    return self;
}

#pragma mark -
#pragma mark Bindings

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
#else

-(Class)valueClassForBinding:(NSString *)binding
{
    return [NSArray class];
}

#endif

#pragma mark -
#pragma mark Drawing

-(void)drawInContext:(CGContextRef)theContext
{
    [self reloadDataIfNeeded];
    [super drawInContext:theContext];

    id<CPTPlotDelegate> theDelegate = (id<CPTPlotDelegate>)self.delegate;
    if ( [theDelegate respondsToSelector:@selector(didFinishDrawing:)] ) {
        [theDelegate didFinishDrawing:self];
    }
}

#pragma mark -
#pragma mark Animation

+(BOOL)needsDisplayForKey:(NSString *)aKey
{
    static NSArray *keys = nil;

    if ( !keys ) {
        keys = [[NSArray alloc] initWithObjects:
                @"labelOffset",
                @"labelRotation",
                nil];
    }

    if ( [keys containsObject:aKey] ) {
        return YES;
    }
    else {
        return [super needsDisplayForKey:aKey];
    }
}

#pragma mark -
#pragma mark Layout

-(void)layoutSublayers
{
    [self relabel];
    [super layoutSublayers];
}

#pragma mark -
#pragma mark Data Source

/**
 *	@brief Marks the receiver as needing the data source reloaded before the content is next drawn.
 **/
-(void)setDataNeedsReloading
{
    self.dataNeedsReloading = YES;
}

/**
 *	@brief Reload all plot data from the data source immediately.
 **/
-(void)reloadData
{
    [self.cachedData removeAllObjects];
    self.cachedDataCount = 0;
    [self reloadDataInIndexRange:NSMakeRange(0, [self.dataSource numberOfRecordsForPlot:self])];
}

/**
 *	@brief Reload plot data from the data source only if the data cache is out of date.
 **/
-(void)reloadDataIfNeeded
{
    if ( self.dataNeedsReloading ) {
        [self reloadData];
    }
}

/**	@brief Reload plot data in the given index range from the data source immediately.
 *	@param indexRange The index range to load.
 **/
-(void)reloadDataInIndexRange:(NSRange)indexRange
{
    NSParameterAssert(NSMaxRange(indexRange) <= [self.dataSource numberOfRecordsForPlot:self]);

    self.dataNeedsReloading = NO;
    [self relabelIndexRange:indexRange];
}

/**	@brief Insert records into the plot data cache at the given index.
 *	@param index The starting index of the new records.
 *	@param numberOfRecords The number of records to insert.
 **/
-(void)insertDataAtIndex:(NSUInteger)index numberOfRecords:(NSUInteger)numberOfRecords
{
    NSParameterAssert(index <= self.cachedDataCount);

    for ( CPTMutableNumericData *numericData in [self.cachedData allValues] ) {
        size_t sampleSize = numericData.sampleBytes;
        size_t length     = sampleSize * numberOfRecords;

        [(NSMutableData *)numericData.data increaseLengthBy:length];

        void *start        = [numericData samplePointer:index];
        size_t bytesToMove = numericData.data.length - (index + numberOfRecords) * sampleSize;
        if ( bytesToMove > 0 ) {
            memmove(start + length, start, bytesToMove);
        }
    }

    self.cachedDataCount += numberOfRecords;
    [self reloadDataInIndexRange:NSMakeRange(index, self.cachedDataCount - index)];
}

/**	@brief Delete records in the given index range from the plot data cache.
 *	@param indexRange The index range of the data records to remove.
 **/
-(void)deleteDataInIndexRange:(NSRange)indexRange
{
    NSParameterAssert(NSMaxRange(indexRange) <= self.cachedDataCount);

    for ( CPTMutableNumericData *numericData in [self.cachedData allValues] ) {
        size_t sampleSize  = numericData.sampleBytes;
        void *start        = [numericData samplePointer:indexRange.location];
        size_t length      = sampleSize * indexRange.length;
        size_t bytesToMove = numericData.data.length - (indexRange.location + indexRange.length) * sampleSize;
        if ( bytesToMove > 0 ) {
            memmove(start, start + length, bytesToMove);
        }

        NSMutableData *dataBuffer = (NSMutableData *)numericData.data;
        dataBuffer.length -= length;
    }

    self.cachedDataCount -= indexRange.length;
    [self relabelIndexRange:NSMakeRange(indexRange.location, self.cachedDataCount - indexRange.location)];
    [self setNeedsDisplay];
}

/**	@brief Gets a range of plot data for the given plot and field.
 *	@param fieldEnum The field index.
 *	@param indexRange The range of the data indexes of interest.
 *	@return An array of data points.
 **/
-(id)numbersFromDataSourceForField:(NSUInteger)fieldEnum recordIndexRange:(NSRange)indexRange
{
    id numbers; // can be CPTNumericData, NSArray, or NSData

    id<CPTPlotDataSource> theDataSource = self.dataSource;

    if ( theDataSource ) {
        if ( [theDataSource respondsToSelector:@selector(dataForPlot:field:recordIndexRange:)] ) {
            numbers = [theDataSource dataForPlot:self field:fieldEnum recordIndexRange:indexRange];
        }
        else if ( [theDataSource respondsToSelector:@selector(doublesForPlot:field:recordIndexRange:)] ) {
            numbers = [NSMutableData dataWithLength:sizeof(double) * indexRange.length];
            double *fieldValues  = [numbers mutableBytes];
            double *doubleValues = [theDataSource doublesForPlot:self field:fieldEnum recordIndexRange:indexRange];
            memcpy(fieldValues, doubleValues, sizeof(double) * indexRange.length);
        }
        else if ( [theDataSource respondsToSelector:@selector(numbersForPlot:field:recordIndexRange:)] ) {
            numbers = [NSArray arrayWithArray:[theDataSource numbersForPlot:self field:fieldEnum recordIndexRange:indexRange]];
        }
        else if ( [theDataSource respondsToSelector:@selector(doubleForPlot:field:recordIndex:)] ) {
            NSUInteger recordIndex;
            NSMutableData *fieldData = [NSMutableData dataWithLength:sizeof(double) * indexRange.length];
            double *fieldValues      = [fieldData mutableBytes];
            for ( recordIndex = indexRange.location; recordIndex < indexRange.location + indexRange.length; ++recordIndex ) {
                double number = [theDataSource doubleForPlot:self field:fieldEnum recordIndex:recordIndex];
                *fieldValues++ = number;
            }
            numbers = fieldData;
        }
        else {
            BOOL respondsToSingleValueSelector = [theDataSource respondsToSelector:@selector(numberForPlot:field:recordIndex:)];
            NSUInteger recordIndex;
            NSMutableArray *fieldValues = [NSMutableArray arrayWithCapacity:indexRange.length];
            for ( recordIndex = indexRange.location; recordIndex < indexRange.location + indexRange.length; recordIndex++ ) {
                if ( respondsToSingleValueSelector ) {
                    NSNumber *number = [theDataSource numberForPlot:self field:fieldEnum recordIndex:recordIndex];
                    if ( number ) {
                        [fieldValues addObject:number];
                    }
                    else {
                        [fieldValues addObject:[NSNull null]];
                    }
                }
                else {
                    [fieldValues addObject:[NSDecimalNumber zero]];
                }
            }
            numbers = fieldValues;
        }
    }
    else {
        numbers = [NSArray array];
    }

    return numbers;
}

#pragma mark -
#pragma mark Data Caching

-(NSUInteger)cachedDataCount
{
    [self reloadDataIfNeeded];
    return cachedDataCount;
}

/**	@brief Copies an array of numbers to the cache.
 *	@param numbers An array of numbers to cache. Can be a CPTNumericData, NSArray, or NSData (NSData is assumed to be a c-style array of type <code>double</code>).
 *	@param fieldEnum The field enumerator identifying the field.
 **/
-(void)cacheNumbers:(id)numbers forField:(NSUInteger)fieldEnum
{
    NSNumber *cacheKey = [NSNumber numberWithUnsignedInteger:fieldEnum];

    if ( numbers ) {
        CPTMutableNumericData *mutableNumbers = [self numericDataForNumbers:numbers];

        NSUInteger sampleCount = mutableNumbers.numberOfSamples;
        if ( sampleCount > 0 ) {
            [self.cachedData setObject:mutableNumbers forKey:cacheKey];
        }
        else {
            [self.cachedData removeObjectForKey:cacheKey];
        }

        self.cachedDataCount = sampleCount;

        switch ( self.cachePrecision ) {
            case CPTPlotCachePrecisionAuto:
                [self setCachedDataType:mutableNumbers.dataType];
                break;

            case CPTPlotCachePrecisionDouble:
                [self setCachedDataType:self.doubleDataType];
                break;

            case CPTPlotCachePrecisionDecimal:
                [self setCachedDataType:self.decimalDataType];
                break;
        }
    }
    else {
        [self.cachedData removeObjectForKey:cacheKey];
        self.cachedDataCount = 0;
    }
    self.needsRelabel = YES;
    [self setNeedsDisplay];
}

/**	@brief Copies an array of numbers to replace a part of the cache.
 *	@param numbers An array of numbers to cache. Can be a CPTNumericData, NSArray, or NSData (NSData is assumed to be a c-style array of type <code>double</code>).
 *	@param fieldEnum The field enumerator identifying the field.
 *	@param index The index of the first data point to replace.
 **/
-(void)cacheNumbers:(id)numbers forField:(NSUInteger)fieldEnum atRecordIndex:(NSUInteger)index
{
    if ( numbers ) {
        CPTMutableNumericData *mutableNumbers = [self numericDataForNumbers:numbers];

        NSUInteger sampleCount = mutableNumbers.numberOfSamples;
        if ( sampleCount > 0 ) {
            // Ensure the new data is the same type as the cache
            switch ( self.cachePrecision ) {
                case CPTPlotCachePrecisionAuto:
                    [self setCachedDataType:mutableNumbers.dataType];
                    break;

                case CPTPlotCachePrecisionDouble:
                {
                    CPTNumericDataType newType = self.doubleDataType;
                    [self setCachedDataType:newType];
                    mutableNumbers.dataType = newType;
                }
                break;

                case CPTPlotCachePrecisionDecimal:
                {
                    CPTNumericDataType newType = self.decimalDataType;
                    [self setCachedDataType:newType];
                    mutableNumbers.dataType = newType;
                }
                break;
            }

            // Ensure the data cache exists and is the right size
            NSNumber *cacheKey                   = [NSNumber numberWithUnsignedInteger:fieldEnum];
            CPTMutableNumericData *cachedNumbers = [self.cachedData objectForKey:cacheKey];
            if ( !cachedNumbers ) {
                cachedNumbers = [CPTMutableNumericData numericDataWithData:[NSData data]
                                                                  dataType:mutableNumbers.dataType
                                                                     shape:nil];
                [self.cachedData setObject:cachedNumbers forKey:cacheKey];
            }
            NSUInteger numberOfRecords = [self.dataSource numberOfRecordsForPlot:self];
            cachedNumbers.shape = [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:numberOfRecords]];

            // Update the cache
            self.cachedDataCount = numberOfRecords;

            NSUInteger startByte = index * cachedNumbers.sampleBytes;
            void *cachePtr       = cachedNumbers.mutableBytes + startByte;
            size_t numberOfBytes = MIN(mutableNumbers.data.length, cachedNumbers.data.length - startByte);
            memcpy(cachePtr, mutableNumbers.bytes, numberOfBytes);

            [self relabelIndexRange:NSMakeRange(index, sampleCount)];
        }
        [self setNeedsDisplay];
    }
}

///	@cond

-(CPTMutableNumericData *)numericDataForNumbers:(id)numbers
{
    CPTMutableNumericData *mutableNumbers = nil;
    CPTNumericDataType loadedDataType;

    if ( [numbers isKindOfClass:[CPTNumericData class]] ) {
        mutableNumbers = [numbers mutableCopy];
        // ensure the numeric data is in a supported format; default to double if not already NSDecimal
        if ( !CPTDataTypeEqualToDataType(mutableNumbers.dataType, self.decimalDataType) ) {
            mutableNumbers.dataType = self.doubleDataType;
        }
    }
    else if ( [numbers isKindOfClass:[NSData class]] ) {
        loadedDataType = self.doubleDataType;
        mutableNumbers = [[CPTMutableNumericData alloc] initWithData:numbers dataType:loadedDataType shape:nil];
    }
    else if ( [numbers isKindOfClass:[NSArray class]] ) {
        if ( ( (NSArray *)numbers ).count == 0 ) {
            loadedDataType = self.doubleDataType;
        }
        else if ( [[(NSArray *) numbers objectAtIndex:0] isKindOfClass:[NSDecimalNumber class]] ) {
            loadedDataType = self.decimalDataType;
        }
        else {
            loadedDataType = self.doubleDataType;
        }

        mutableNumbers = [[CPTMutableNumericData alloc] initWithArray:numbers dataType:loadedDataType shape:nil];
    }
    else {
        [NSException raise:CPTException format:@"Unsupported number array format"];
    }

    return [mutableNumbers autorelease];
}

///	@endcond

-(BOOL)doublePrecisionCache
{
    BOOL result = NO;

    switch ( self.cachePrecision ) {
        case CPTPlotCachePrecisionAuto:
        {
            NSArray *cachedObjects = [self.cachedData allValues];
            if ( cachedObjects.count > 0 ) {
                result = CPTDataTypeEqualToDataType( ( (CPTMutableNumericData *)[cachedObjects objectAtIndex:0] ).dataType, self.doubleDataType );
            }
        }
        break;

        case CPTPlotCachePrecisionDouble:
            result = YES;
            break;

        default:
            // not double precision
            break;
    }
    return result;
}

/**	@brief Retrieves an array of numbers from the cache.
 *	@param fieldEnum The field enumerator identifying the field.
 *	@return The array of cached numbers.
 **/
-(CPTMutableNumericData *)cachedNumbersForField:(NSUInteger)fieldEnum
{
    return [self.cachedData objectForKey:[NSNumber numberWithUnsignedInteger:fieldEnum]];
}

/**	@brief Retrieves a single number from the cache.
 *	@param fieldEnum The field enumerator identifying the field.
 *	@param index The index of the desired data value.
 *	@return The cached number.
 **/
-(NSNumber *)cachedNumberForField:(NSUInteger)fieldEnum recordIndex:(NSUInteger)index
{
    CPTMutableNumericData *numbers = [self cachedNumbersForField:fieldEnum];

    return [numbers sampleValue:index];
}

/**	@brief Retrieves a single number from the cache.
 *	@param fieldEnum The field enumerator identifying the field.
 *	@param index The index of the desired data value.
 *	@return The cached number or NAN if no data is cached for the requested field.
 **/
-(double)cachedDoubleForField:(NSUInteger)fieldEnum recordIndex:(NSUInteger)index
{
    CPTMutableNumericData *numbers = [self cachedNumbersForField:fieldEnum];

    if ( numbers ) {
        switch ( numbers.dataTypeFormat ) {
            case CPTFloatingPointDataType:
            {
                double *doubleNumber = (double *)[numbers samplePointer:index];
                if ( doubleNumber ) {
                    return *doubleNumber;
                }
            }
            break;

            case CPTDecimalDataType:
            {
                NSDecimal *decimalNumber = (NSDecimal *)[numbers samplePointer:index];
                if ( decimalNumber ) {
                    return CPTDecimalDoubleValue(*decimalNumber);
                }
            }
            break;

            default:
                [NSException raise:CPTException format:@"Unsupported data type format"];
                break;
        }
    }
    return NAN;
}

/**	@brief Retrieves a single number from the cache.
 *	@param fieldEnum The field enumerator identifying the field.
 *	@param index The index of the desired data value.
 *	@return The cached number or NAN if no data is cached for the requested field.
 **/
-(NSDecimal)cachedDecimalForField:(NSUInteger)fieldEnum recordIndex:(NSUInteger)index
{
    CPTMutableNumericData *numbers = [self cachedNumbersForField:fieldEnum];

    if ( numbers ) {
        switch ( numbers.dataTypeFormat ) {
            case CPTFloatingPointDataType:
            {
                double *doubleNumber = (double *)[numbers samplePointer:index];
                if ( doubleNumber ) {
                    return CPTDecimalFromDouble(*doubleNumber);
                }
            }
            break;

            case CPTDecimalDataType:
            {
                NSDecimal *decimalNumber = (NSDecimal *)[numbers samplePointer:index];
                if ( decimalNumber ) {
                    return *decimalNumber;
                }
            }
            break;

            default:
                [NSException raise:CPTException format:@"Unsupported data type format"];
                break;
        }
    }
    return CPTDecimalNaN();
}

///	@cond

-(void)setCachedDataType:(CPTNumericDataType)newDataType
{
    for ( CPTMutableNumericData *numericData in [self.cachedData allValues] ) {
        numericData.dataType = newDataType;
    }
}

///	@endcond

-(CPTNumericDataType)doubleDataType
{
    return CPTDataType( CPTFloatingPointDataType, sizeof(double), CFByteOrderGetCurrent() );
}

-(CPTNumericDataType)decimalDataType
{
    return CPTDataType( CPTDecimalDataType, sizeof(NSDecimal), CFByteOrderGetCurrent() );
}

#pragma mark -
#pragma mark Data Ranges

/**	@brief Determines the smallest plot range that fully encloses the data for a particular field.
 *	@param fieldEnum The field enumerator identifying the field.
 *	@return The plot range enclosing the data.
 **/
-(CPTPlotRange *)plotRangeForField:(NSUInteger)fieldEnum
{
    if ( self.dataNeedsReloading ) {
        [self reloadData];
    }
    CPTMutableNumericData *numbers = [self cachedNumbersForField:fieldEnum];
    CPTPlotRange *range            = nil;

    NSUInteger numberOfSamples = numbers.numberOfSamples;
    if ( numberOfSamples > 0 ) {
        if ( self.doublePrecisionCache ) {
            // TODO: Should use Accelerate framework for min and max as soon as the minimum iOS version is 4.0

            double min = INFINITY;
            double max = -INFINITY;

            const double *doubles    = (const double *)numbers.bytes;
            const double *lastSample = doubles + numberOfSamples;
            while ( doubles < lastSample ) {
                double value = *doubles++;

                if ( !isnan(value) ) {
                    min = MIN(min, value);
                    max = MAX(max, value);
                }
            }

            if ( max >= min ) {
                range = [CPTPlotRange plotRangeWithLocation:CPTDecimalFromDouble(min) length:CPTDecimalFromDouble(max - min)];
            }
        }
        else {
            NSDecimal min = [[NSDecimalNumber maximumDecimalNumber] decimalValue];
            NSDecimal max = [[NSDecimalNumber minimumDecimalNumber] decimalValue];

            const NSDecimal *decimals   = (const NSDecimal *)numbers.bytes;
            const NSDecimal *lastSample = decimals + numberOfSamples;
            while ( decimals < lastSample ) {
                NSDecimal value = *decimals++;

                if ( !NSDecimalIsNotANumber(&value) ) {
                    if ( CPTDecimalLessThan(value, min) ) {
                        min = value;
                    }
                    if ( CPTDecimalGreaterThan(value, max) ) {
                        max = value;
                    }
                }
            }

            if ( CPTDecimalGreaterThanOrEqualTo(max, min) ) {
                range = [CPTPlotRange plotRangeWithLocation:min length:CPTDecimalSubtract(max, min)];
            }
        }
    }
    return range;
}

/**	@brief Determines the smallest plot range that fully encloses the data for a particular coordinate.
 *	@param coord The coordinate identifier.
 *	@return The plot range enclosing the data.
 **/
-(CPTPlotRange *)plotRangeForCoordinate:(CPTCoordinate)coord
{
    NSArray *fields = [self fieldIdentifiersForCoordinate:coord];

    if ( fields.count == 0 ) {
        return nil;
    }

    CPTMutablePlotRange *unionRange = nil;
    for ( NSNumber *field in fields ) {
        CPTPlotRange *currentRange = [self plotRangeForField:field.unsignedIntValue];
        if ( !unionRange ) {
            unionRange = [[currentRange mutableCopy] autorelease];
        }
        else {
            [unionRange unionPlotRange:[self plotRangeForField:field.unsignedIntValue]];
        }
    }

    return unionRange;
}

#pragma mark -
#pragma mark Data Labels

/**
 *	@brief Marks the receiver as needing to update all data labels before the content is next drawn.
 *	@see relabelIndexRange()
 **/
-(void)setNeedsRelabel
{
    self.labelIndexRange = NSMakeRange(0, self.cachedDataCount);
    self.needsRelabel    = YES;
}

/**
 *	@brief Updates the data labels in the labelIndexRange.
 **/
-(void)relabel
{
    if ( !self.needsRelabel ) {
        return;
    }

    self.needsRelabel = NO;

    id<CPTPlotDataSource> theDataSource   = self.dataSource;
    CPTTextStyle *dataLabelTextStyle      = self.labelTextStyle;
    NSNumberFormatter *dataLabelFormatter = self.labelFormatter;

    BOOL dataSourceProvidesLabels = [theDataSource respondsToSelector:@selector(dataLabelForPlot:recordIndex:)];
    BOOL plotProvidesLabels       = dataLabelTextStyle && dataLabelFormatter;

    if ( !dataSourceProvidesLabels && !plotProvidesLabels ) {
        Class annotationClass = [CPTAnnotation class];
        for ( CPTAnnotation *annotation in self.labelAnnotations ) {
            if ( [annotation isKindOfClass:annotationClass] ) {
                [self removeAnnotation:annotation];
            }
        }
        self.labelAnnotations = nil;
        return;
    }

    NSUInteger sampleCount = self.cachedDataCount;
    NSRange indexRange     = self.labelIndexRange;
    NSUInteger maxIndex    = NSMaxRange(indexRange);

    if ( !self.labelAnnotations ) {
        self.labelAnnotations = [NSMutableArray arrayWithCapacity:sampleCount];
    }

    CPTPlotSpace *thePlotSpace = self.plotSpace;
    CGFloat theRotation        = self.labelRotation;
    NSMutableArray *labelArray = self.labelAnnotations;
    NSUInteger oldLabelCount   = labelArray.count;

    Class annotationClass = [CPTAnnotation class];
    Class nullClass       = [NSNull class];

    CPTMutableNumericData *labelFieldDataCache = [self cachedNumbersForField:self.labelField];
    CPTShadow *theShadow                       = self.labelShadow;

    for ( NSUInteger i = indexRange.location; i < maxIndex; i++ ) {
        CPTLayer *newLabelLayer = nil;

        NSNumber *dataValue = [labelFieldDataCache sampleValue:i];

        if ( isnan([dataValue doubleValue]) ) {
            newLabelLayer = nil;
        }
        else {
            if ( dataSourceProvidesLabels ) {
                newLabelLayer = [[theDataSource dataLabelForPlot:self recordIndex:i] retain];
            }

            if ( !newLabelLayer && plotProvidesLabels ) {
                NSString *labelString = [dataLabelFormatter stringForObjectValue:dataValue];
                newLabelLayer = [[CPTTextLayer alloc] initWithText:labelString style:dataLabelTextStyle];
            }

            if ( [newLabelLayer isKindOfClass:nullClass] ) {
                [newLabelLayer release];
                newLabelLayer = nil;
            }
        }
        newLabelLayer.shadow = theShadow;

        CPTPlotSpaceAnnotation *labelAnnotation;
        if ( i < oldLabelCount ) {
            labelAnnotation = [labelArray objectAtIndex:i];
            if ( newLabelLayer ) {
                if ( [labelAnnotation isKindOfClass:nullClass] ) {
                    labelAnnotation = [[CPTPlotSpaceAnnotation alloc] initWithPlotSpace:thePlotSpace anchorPlotPoint:nil];
                    [labelArray replaceObjectAtIndex:i withObject:labelAnnotation];
                    [self addAnnotation:labelAnnotation];
                    [labelAnnotation release];
                }
            }
            else {
                if ( [labelAnnotation isKindOfClass:annotationClass] ) {
                    [labelArray replaceObjectAtIndex:i withObject:[NSNull null]];
                    [self removeAnnotation:labelAnnotation];
                }
            }
        }
        else {
            if ( newLabelLayer ) {
                labelAnnotation = [[CPTPlotSpaceAnnotation alloc] initWithPlotSpace:thePlotSpace anchorPlotPoint:nil];
                [labelArray addObject:labelAnnotation];
                [self addAnnotation:labelAnnotation];
                [labelAnnotation release];
            }
            else {
                [labelArray addObject:[NSNull null]];
            }
        }

        if ( newLabelLayer ) {
            labelAnnotation.contentLayer = newLabelLayer;
            labelAnnotation.rotation     = theRotation;
            [self positionLabelAnnotation:labelAnnotation forIndex:i];
            [self updateContentAnchorForLabel:labelAnnotation];

            [newLabelLayer release];
        }
    }

    // remove labels that are no longer needed
    while ( labelArray.count > sampleCount ) {
        CPTAnnotation *oldAnnotation = [labelArray objectAtIndex:labelArray.count - 1];
        if ( [oldAnnotation isKindOfClass:annotationClass] ) {
            [self removeAnnotation:oldAnnotation];
        }
        [labelArray removeLastObject];
    }
}

/**	@brief Marks the receiver as needing to update a range of data labels before the content is next drawn.
 *	@param indexRange The new indexRange for the labels.
 *	@see setNeedsRelabel()
 **/
-(void)relabelIndexRange:(NSRange)indexRange
{
    self.labelIndexRange = indexRange;
    self.needsRelabel    = YES;
}

///	@cond

-(void)updateContentAnchorForLabel:(CPTPlotSpaceAnnotation *)label
{
    if ( label ) {
        CGPoint displacement = label.displacement;
        if ( CGPointEqualToPoint(displacement, CGPointZero) ) {
            displacement.y = 1.0; // put the label above the data point if zero displacement
        }
        CGFloat angle      = (CGFloat)M_PI + atan2(displacement.y, displacement.x) - label.rotation;
        CGFloat newAnchorX = cos(angle);
        CGFloat newAnchorY = sin(angle);

        if ( ABS(newAnchorX) <= ABS(newAnchorY) ) {
            newAnchorX /= ABS(newAnchorY);
            newAnchorY  = signbit(newAnchorY) ? -1.0 : 1.0;
        }
        else {
            newAnchorY /= ABS(newAnchorX);
            newAnchorX  = signbit(newAnchorX) ? -1.0 : 1.0;
        }

        label.contentAnchorPoint = CGPointMake( (newAnchorX + (CGFloat)1.0) / (CGFloat)2.0, (newAnchorY + (CGFloat)1.0) / (CGFloat)2.0 );
    }
}

///	@endcond

/**
 *	@brief Repositions all existing label annotations.
 **/
-(void)repositionAllLabelAnnotations
{
    NSArray *annotations  = self.labelAnnotations;
    NSUInteger labelCount = annotations.count;
    Class annotationClass = [CPTAnnotation class];

    for ( NSUInteger i = 0; i < labelCount; i++ ) {
        CPTPlotSpaceAnnotation *annotation = [annotations objectAtIndex:i];
        if ( [annotation isKindOfClass:annotationClass] ) {
            [self positionLabelAnnotation:annotation forIndex:i];
            [self updateContentAnchorForLabel:annotation];
        }
    }
}

#pragma mark -
#pragma mark Legends

/**	@brief The number of legend entries provided by this plot.
 *	@return The number of legend entries.
 **/
-(NSUInteger)numberOfLegendEntries
{
    return 1;
}

/**	@brief The title text of a legend entry.
 *	@param index The index of the desired title.
 *	@return The title of the legend entry at the requested index.
 **/
-(NSString *)titleForLegendEntryAtIndex:(NSUInteger)index
{
    NSString *legendTitle = self.title;

    if ( !legendTitle ) {
        if ( [self.identifier isKindOfClass:[NSString class]] ) {
            legendTitle = (NSString *)self.identifier;
        }
    }

    return legendTitle;
}

/**	@brief Draws the legend swatch of a legend entry.
 *	Subclasses should call super to draw the background fill and border.
 *	@param legend The legend being drawn.
 *	@param index The index of the desired swatch.
 *	@param rect The bounding rectangle where the swatch should be drawn.
 *	@param context The graphics context to draw into.
 **/
-(void)drawSwatchForLegend:(CPTLegend *)legend atIndex:(NSUInteger)index inRect:(CGRect)rect inContext:(CGContextRef)context
{
    CPTFill *theFill           = legend.swatchFill;
    CPTLineStyle *theLineStyle = legend.swatchBorderLineStyle;

    if ( theFill || theLineStyle ) {
        CGPathRef swatchPath;
        CGFloat radius = legend.swatchCornerRadius;
        if ( radius > 0.0 ) {
            radius     = MIN(MIN(radius, rect.size.width / (CGFloat)2.0), rect.size.height / (CGFloat)2.0);
            swatchPath = CreateRoundedRectPath(rect, radius);
        }
        else {
            CGMutablePathRef mutablePath = CGPathCreateMutable();
            CGPathAddRect(mutablePath, NULL, rect);
            swatchPath = mutablePath;
        }

        if ( theFill ) {
            CGContextBeginPath(context);
            CGContextAddPath(context, swatchPath);
            [theFill fillPathInContext:context];
        }

        if ( theLineStyle ) {
            [theLineStyle setLineStyleInContext:context];
            CGContextBeginPath(context);
            CGContextAddPath(context, swatchPath);
            [theLineStyle strokePathInContext:context];
        }

        CGPathRelease(swatchPath);
    }
}

#pragma mark -
#pragma mark Responder Chain and User interaction

/// @name User Interaction
/// @{

/**
 *	@brief Informs the receiver that the user has
 *	@if MacOnly pressed the mouse button. @endif
 *	@if iOSOnly touched the screen. @endif
 *
 *
 *	If this plot has a delegate that responds to the
 *	@link CPTPlotDelegate::plot:dataLabelWasSelectedAtRecordIndex: -plot:dataLabelWasSelectedAtRecordIndex: @endlink and/or
 *	@link CPTPlotDelegate::plot:dataLabelWasSelectedAtRecordIndex:withEvent: -plot:dataLabelWasSelectedAtRecordIndex:withEvent: @endlink
 *	methods, the data labels are searched to find the index of the one containing the <code>interactionPoint</code>.
 *	The delegate method will be called and this method returns <code>YES</code> if the <code>interactionPoint</code> is within a label.
 *	This method returns <code>NO</code> if the <code>interactionPoint</code> is too far away from all of the data labels.
 *
 *	@param event The OS event.
 *	@param interactionPoint The coordinates of the interaction.
 *  @return Whether the event was handled or not.
 **/
-(BOOL)pointingDeviceDownEvent:(CPTNativeEvent *)event atPoint:(CGPoint)interactionPoint
{
    CPTGraph *theGraph = self.graph;

    if ( !theGraph ) {
        return NO;
    }

    id<CPTPlotDelegate> theDelegate = self.delegate;
    if ( [theDelegate respondsToSelector:@selector(plot:dataLabelWasSelectedAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector(plot:dataLabelWasSelectedAtRecordIndex:withEvent:)] ) {
        // Inform delegate if a label was hit
        NSMutableArray *labelArray = self.labelAnnotations;
        NSUInteger labelCount      = labelArray.count;
        Class annotationClass      = [CPTAnnotation class];

        for ( NSUInteger index = 0; index < labelCount; index++ ) {
            CPTPlotSpaceAnnotation *annotation = [labelArray objectAtIndex:index];
            if ( [annotation isKindOfClass:annotationClass] ) {
                CPTLayer *labelLayer = annotation.contentLayer;
                if ( labelLayer ) {
                    CGPoint labelPoint = [theGraph convertPoint:interactionPoint toLayer:labelLayer];

                    if ( CGRectContainsPoint(labelLayer.bounds, labelPoint) ) {
                        if ( [theDelegate respondsToSelector:@selector(plot:dataLabelWasSelectedAtRecordIndex:)] ) {
                            [theDelegate plot:self dataLabelWasSelectedAtRecordIndex:index];
                        }
                        if ( [theDelegate respondsToSelector:@selector(plot:dataLabelWasSelectedAtRecordIndex:withEvent:)] ) {
                            [theDelegate plot:self dataLabelWasSelectedAtRecordIndex:index withEvent:event];
                        }
                        return YES;
                    }
                }
            }
        }
    }

    return [super pointingDeviceDownEvent:event atPoint:interactionPoint];
}

///	@}

#pragma mark -
#pragma mark Accessors

///	@cond

-(void)setTitle:(NSString *)newTitle
{
    if ( newTitle != title ) {
        [title release];
        title = [newTitle copy];
        [[NSNotificationCenter defaultCenter] postNotificationName:CPTLegendNeedsLayoutForPlotNotification object:self];
    }
}

-(void)setDataSource:(id<CPTPlotDataSource>)newSource
{
    if ( newSource != dataSource ) {
        dataSource = newSource;
        [self setDataNeedsReloading];
    }
}

-(void)setDataNeedsReloading:(BOOL)newDataNeedsReloading
{
    if ( newDataNeedsReloading != dataNeedsReloading ) {
        dataNeedsReloading = newDataNeedsReloading;
        if ( dataNeedsReloading ) {
            [self setNeedsDisplay];
        }
    }
}

-(CPTPlotArea *)plotArea
{
    return self.graph.plotAreaFrame.plotArea;
}

-(void)setNeedsRelabel:(BOOL)newNeedsRelabel
{
    if ( newNeedsRelabel != needsRelabel ) {
        needsRelabel = newNeedsRelabel;
        if ( needsRelabel ) {
            [self setNeedsLayout];
        }
    }
}

-(void)setLabelTextStyle:(CPTTextStyle *)newStyle
{
    if ( newStyle != labelTextStyle ) {
        [labelTextStyle release];
        labelTextStyle = [newStyle copy];

        if ( labelTextStyle && !self.labelFormatter ) {
            NSNumberFormatter *newFormatter = [[NSNumberFormatter alloc] init];
            newFormatter.minimumIntegerDigits  = 1;
            newFormatter.maximumFractionDigits = 1;
            newFormatter.minimumFractionDigits = 1;
            self.labelFormatter                = newFormatter;
            [newFormatter release];
        }

        self.needsRelabel = YES;
    }
}

-(void)setLabelOffset:(CGFloat)newOffset
{
    if ( newOffset != labelOffset ) {
        labelOffset = newOffset;
        [self repositionAllLabelAnnotations];
    }
}

-(void)setLabelRotation:(CGFloat)newRotation
{
    if ( newRotation != labelRotation ) {
        labelRotation = newRotation;

        Class annotationClass = [CPTAnnotation class];
        for ( CPTPlotSpaceAnnotation *label in self.labelAnnotations ) {
            if ( [label isKindOfClass:annotationClass] ) {
                label.rotation = labelRotation;
                [self updateContentAnchorForLabel:label];
            }
        }
    }
}

-(void)setLabelFormatter:(NSNumberFormatter *)newTickLabelFormatter
{
    if ( newTickLabelFormatter != labelFormatter ) {
        [labelFormatter release];
        labelFormatter    = [newTickLabelFormatter retain];
        self.needsRelabel = YES;
    }
}

-(void)setLabelShadow:(CPTShadow *)newLabelShadow
{
    if ( newLabelShadow != labelShadow ) {
        [labelShadow release];
        labelShadow = [newLabelShadow retain];

        Class annotationClass = [CPTAnnotation class];
        for ( CPTAnnotation *label in self.labelAnnotations ) {
            if ( [label isKindOfClass:annotationClass] ) {
                label.contentLayer.shadow = labelShadow;
            }
        }
    }
}

-(void)setCachePrecision:(CPTPlotCachePrecision)newPrecision
{
    if ( newPrecision != cachePrecision ) {
        cachePrecision = newPrecision;
        switch ( cachePrecision ) {
            case CPTPlotCachePrecisionAuto:
                // don't change data already in the cache
                break;

            case CPTPlotCachePrecisionDouble:
                [self setCachedDataType:self.doubleDataType];
                break;

            case CPTPlotCachePrecisionDecimal:
                [self setCachedDataType:self.decimalDataType];
                break;

            default:
                [NSException raise:NSInvalidArgumentException format:@"Invalid cache precision"];
                break;
        }
    }
}

-(void)setAlignsPointsToPixels:(BOOL)newAlignsPointsToPixels
{
    if ( newAlignsPointsToPixels != alignsPointsToPixels ) {
        alignsPointsToPixels = newAlignsPointsToPixels;
        [self setNeedsDisplay];
    }
}

///	@endcond

@end

#pragma mark -

@implementation CPTPlot(AbstractMethods)

#pragma mark -
#pragma mark Fields

/**	@brief Number of fields in a plot data record.
 *	@return The number of fields.
 **/
-(NSUInteger)numberOfFields
{
    return 0;
}

/**	@brief Identifiers (enum values) identifying the fields.
 *	@return Array of NSNumber objects for the various field identifiers.
 **/
-(NSArray *)fieldIdentifiers
{
    return [NSArray array];
}

/**	@brief The field identifiers that correspond to a particular coordinate.
 *  @param coord The coordinate for which the corresponding field identifiers are desired.
 *	@return Array of NSNumber objects for the field identifiers.
 **/
-(NSArray *)fieldIdentifiersForCoordinate:(CPTCoordinate)coord
{
    return [NSArray array];
}

#pragma mark -
#pragma mark Data Labels

/**	@brief Adjusts the position of the data label annotation for the plot point at the given index.
 *  @param label The annotation for the data label.
 *  @param index The data index for the label.
 **/
-(void)positionLabelAnnotation:(CPTPlotSpaceAnnotation *)label forIndex:(NSUInteger)index
{
    // do nothing--implementation provided by subclasses
}

#pragma mark -
#pragma mark User Interaction

/**
 *	@brief Determines the index of the data element that's under the given point.
 *	@param point The coordinates of the interaction.
 *  @return The index of the data point that's under the given point or NSNotFound if none was found.
 */
-(NSUInteger)dataIndexFromInteractionPoint:(CGPoint)point
{
    return NSNotFound;
}

@end
